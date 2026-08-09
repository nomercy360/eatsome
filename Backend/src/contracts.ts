import * as z from "zod";

export const foodGroups = [
  "olive_oil",
  "vegetables",
  "fruit",
  "legumes",
  "fish",
  "nuts",
  "healthy_fats",
  "whole_grains",
  "refined_grains",
  "white_meat",
  "red_meat",
  "processed_meat",
  "dairy",
  "egg",
  "sweets",
  "pastry",
  "sugary_drinks",
  "coffee",
  "tea",
  "juice",
  "plant_milk",
  "smoothie",
  "butter",
  "alcohol",
  "sofrito",
  "other",
] as const;

/**
 * Stored only. No prompt asks for one and no schema the model sees carries one
 * from v17; this stays because `mealItemSchema` syncs events written before it,
 * and the log is append-only.
 */
export const portions = ["small", "medium", "large"] as const;

/// Both answer the same contract and the same prompt, so a device can switch
/// and the eval rows stay comparable. Which one served a request is recorded on
/// the recognition row, and the cache keys on the model.
export const recognitionProviders = [
  "openai",
  "gemini",
  "anthropic",
  "qwen",
  "openrouter",
] as const;
export type RecognitionProvider = (typeof recognitionProviders)[number];
export const eventKinds = [
  "meal_logged",
  "meal_revised",
  "meal_deleted",
  "set_completed",
  "habits_updated",
  "recipe_saved",
  "recipe_deleted",
] as const;

export const sha256Schema = z
  .string()
  .regex(/^[a-f0-9]{64}$/i, "Expected a 64-character SHA-256 hex digest.");

const rawJsonSchema = z
  .string()
  .min(2)
  .max(200_000)
  .refine((value) => {
    try {
      JSON.parse(value);
      return true;
    } catch {
      return false;
    }
  }, "Expected valid raw model JSON.");

export const mealRecognitionItemSchema = z.strictObject({
  group: z.enum(foodGroups),
  // Edible weight on the plate, absolute: everything of this ingredient that is
  // there, across every serving present. Nothing multiplies it by the dish's
  // count afterwards.
  //
  // Required, and the only quantity asked for. It was nullable while `portion`
  // stood behind it, and a fallback is exactly what let the production Gemini
  // schema omit the field for a month without anything failing — every answer
  // parsed, and every answer was scored on the ladder grams had replaced. With
  // nothing behind it, a weightless answer is now a loud one.
  grams: z.number().min(0).max(20_000),
  label: z.string().max(200).nullable(),
  // Uncertainty is a shortlist of rival groups, not a number. A model asked to
  // score its own certainty returns the same round value for every item on the
  // plate; asked what else the food could be, it answers about the food — and
  // the answer doubles as the one-tap correction in the client.
  alternatives: z.array(z.enum(foodGroups)),
});

/**
 * One named thing on the tray, and what it is made of.
 *
 * `count` is how many servings of the dish are present, and it is a label
 * rather than a factor: the ingredients below already weigh every serving that
 * is there. The client's stepper rewrites those weights when the count is
 * corrected, so the number never multiplies anything at score time.
 */
/**
 * A nutrition panel transcribed off packaging, for one serving as the label
 * defines it.
 *
 * Read, never estimated — that distinction is the whole justification for the
 * field existing. A model asked for grams from pixels returns a number with
 * 30–50% error that is indistinguishable from data; a model reading a printed
 * panel is doing OCR on a fact. Every field is nullable because an unreadable
 * figure must be able to come back absent: a fabricated number stored in the
 * one place reserved for confirmed values is worse than no value at all.
 */
export const panelBases = ["per_100ml", "per_100g", "per_serving", "per_container"] as const;

export const nutritionPanelSchema = z.strictObject({
  protein: z.number().min(0).max(500).nullable(),
  calories: z.number().min(0).max(5_000).nullable(),
  fat: z.number().min(0).max(500).nullable(),
  carbohydrate: z.number().min(0).max(1_000).nullable(),
  /** Grams of salt equivalent — 食塩相当量, which is what Japanese labels print.
   *  Separate from `sodium` because a model given only one field converts into
   *  it silently, twice observed, and a converted figure is indistinguishable
   *  from a read one. */
  salt: z.number().min(0).max(100).nullable(),
  sodium: z.number().min(0).max(100).nullable(),
  /** Milligrams. */
  caffeine: z.number().min(0).max(2_000).nullable(),
  /**
   * What the figures are counted against, copied from the heading above them.
   * A number without this has no unit: `carbohydrate: 1` is true per 100ml of a
   * Monster and wrong by 3.55x for the can, and nothing downstream can tell.
   */
  basis: z.enum(panelBases).nullable(),
  /** Contents as printed — 355 for 「内容量: 355ml」. What lets a per-100ml
   *  panel be scaled to the container, by code rather than by the model. */
  net_ml: z.number().min(0).max(10_000).nullable(),
  net_g: z.number().min(0).max(10_000).nullable(),
});

export type NutritionPanel = z.infer<typeof nutritionPanelSchema>;

const PANEL_FIGURES = [
  "protein",
  "calories",
  "fat",
  "carbohydrate",
  "salt",
  "sodium",
  "caffeine",
] as const;

/** Salt is sodium chloride: 2.54 g of salt carries 1 g of sodium. */
const SODIUM_PER_SALT = 1 / 2.54;

/**
 * The panel as one container's worth, which is what a person consumed: a can, a
 * carton, a cup.
 *
 * The multiplication happens here rather than in the prompt because a model
 * that does arithmetic does it invisibly — the same freedom that turned 0.1g of
 * salt into "~0.04g sodium" unasked. Transcribed facts in, deterministic maths
 * out, and a panel that cannot be scaled keeps its figures and says so through
 * `basis` rather than pretending to be per-container.
 */
export function panelPerContainer(panel: NutritionPanel | null): NutritionPanel | null {
  if (!panel) return null;
  const factor =
    panel.basis === "per_container" || panel.basis === "per_serving"
      ? 1
      : panel.basis === "per_100ml" && panel.net_ml
        ? panel.net_ml / 100
        : panel.basis === "per_100g" && panel.net_g
          ? panel.net_g / 100
          : null;
  // Unscalable: no basis, or a per-100 panel with no printed contents. The
  // figures stay exactly as read, because inventing the missing volume is the
  // one thing worse than leaving the number in its own unit.
  if (factor === null) return withSodium(panel);
  const scaled: NutritionPanel = { ...panel, basis: "per_container" };
  for (const field of PANEL_FIGURES) {
    const value = panel[field];
    if (value != null) scaled[field] = Math.round(value * factor * 100) / 100;
  }
  return withSodium(scaled);
}

/** Sodium from salt, when the label printed the one and not the other. */
function withSodium(panel: NutritionPanel): NutritionPanel {
  if (panel.sodium != null || panel.salt == null) return panel;
  return { ...panel, sodium: Math.round(panel.salt * SODIUM_PER_SALT * 1000) / 1000 };
}

export const mealDishSchema = z.strictObject({
  name: z.string().min(1).max(120),
  count: z.number().int().min(1).max(24),
  ingredients: z.array(mealRecognitionItemSchema).max(24),
  /** Null for almost all food, which has nothing printed on it. */
  panel: nutritionPanelSchema.nullable(),
});

export const mealRecognitionSchema = z.strictObject({
  dishes: z.array(mealDishSchema).max(16),
  other_meals_visible: z.boolean(),
  notes: z.string().max(2_000).nullable(),
});

export type MealRecognition = z.infer<typeof mealRecognitionSchema>;

/**
 * A flattened ingredient. `grams` is the whole quantity now, so `servings` is
 * always null — kept in the shape rather than deleted because the field is what
 * a client checks to find out whether the server did the arithmetic, and an
 * absent field and a null one should not have to mean different things.
 *
 * Dropping `portion` from here is the one breaking change in this contract: a
 * client built before v17 requires it and fails to decode without it. Worker and
 * app ship together. There is no derived stand-in on purpose — turning grams
 * back into small/medium/large needs a serving-weight table, that table lives in
 * `shaman-config.json` on the client, and a second copy of it here is how the
 * two start disagreeing.
 */
export const mealFlatItemSchema = mealRecognitionItemSchema.extend({
  servings: z.number().min(0).nullable(),
  dish: z.string().max(120).nullable(),
});

/**
 * What the client receives: the dishes, plus the flat list the scorer has
 * always used. Builds shipped before dishes existed read `items` and ignore the
 * rest, so the structure can change without stranding a phone in the field.
 */
export const mealRecognitionPayloadSchema = mealRecognitionSchema.extend({
  items: z.array(mealFlatItemSchema).max(64),
});

export type MealRecognitionPayload = z.infer<typeof mealRecognitionPayloadSchema>;

/**
 * The flat list the client scores from.
 *
 * There is no arithmetic left to do. An ingredient's grams already cover every
 * serving present, so `servings` is null on every row — the `count × size ×
 * portion` product that used to live here is the thing v17 removed, and the
 * reason is that it compounded: the model called a bowl of ramen large and its
 * noodles large, and one bowl came out worth 126 g of protein.
 */
export function flattenDishes(recognition: MealRecognition): MealRecognitionPayload {
  return {
    ...recognition,
    dishes: recognition.dishes.map((dish) => ({ ...dish, panel: panelPerContainer(dish.panel) })),
    items: recognition.dishes.flatMap((dish) =>
      dish.ingredients.map((ingredient) => ({
        ...ingredient,
        dish: dish.name,
        servings: null,
      })),
    ),
  };
}

export function mealRecognitionJsonSchema(): Record<string, unknown> {
  const schema = z.toJSONSchema(mealRecognitionSchema, { target: "draft-07" });
  delete schema.$schema;
  return schema;
}

/**
 * A logged meal arrives as a photograph, as the person's own words — typed or
 * dictated — or as both at once, so the image is optional. It is three fields
 * that only mean anything together, which is why they are optional as a unit:
 * a request carrying some of them is malformed, not text-only.
 *
 * `said` is deliberately not `note`. The note is a supplement to a
 * photograph — "what the photo cannot show", evidence attached to an image the
 * model still reads for itself — while `said` IS the input: for a text-only
 * meal it is everything the model has, and for a captioned photo it is the
 * person describing the meal rather than annotating the reading. The prompt
 * frames the two differently, and folding them into one field would either
 * promote every note to a description or demote every description to a
 * footnote. The client sends the words without knowing which they are —
 * whether they caption an image is visible only here, where both fields meet.
 */
export const recognitionRequestSchema = z
  .strictObject({
    // Absent means the server's default, so an older client keeps working.
    provider: z.enum(recognitionProviders).optional(),
    photoHash: sha256Schema.optional(),
    mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]).optional(),
    imageBase64: z
      .string()
      .min(16)
      .max(12_000_000)
      .regex(/^[A-Za-z0-9+/]*={0,2}$/)
      .optional(),
    /** What the person said about the meal — typed or dictated, in their words. */
    said: z.string().max(2_000).nullable().optional(),
    // The note changes the question, so it is part of the recognition cache
    // fingerprint, and so is `said`. "Fried in butter" must not replay the
    // answer produced before the person supplied that fact.
    note: z.string().max(2_000).nullable().optional(),
  })
  .superRefine((request, context) => {
    const image = [request.photoHash, request.mimeType, request.imageBase64];
    const supplied = image.filter((field) => field !== undefined).length;
    if (supplied !== 0 && supplied !== image.length) {
      context.addIssue({
        code: "custom",
        message: "An image is photoHash, mimeType and imageBase64 together, or none of them.",
      });
    }
    // An empty message must be a loud 400, not a model call about nothing.
    if (supplied === 0 && !request.said?.trim()) {
      context.addIssue({
        code: "custom",
        message: "A recognition needs a photograph or a message; this carries neither.",
      });
    }
  });

export type RecognitionRequest = z.infer<typeof recognitionRequestSchema>;

export const rerunRecognitionRequestSchema = z.strictObject({
  provider: z.enum(recognitionProviders).optional(),
  note: z.string().max(2_000).nullable().optional(),
  // A menu action means "ask again", not "show me the cache again". The
  // switch remains explicit so diagnostics can exercise the stored-input path
  // without buying another inference.
  refresh: z.boolean().default(true),
});

export type RerunRecognitionRequest = z.infer<typeof rerunRecognitionRequestSchema>;

export const refinementItemSchema = z.strictObject({
  group: z.enum(foodGroups),
  // Nullable here and nowhere else in the recognition path: this is the list as
  // it stands on the person's phone, and a meal logged before grams — or added
  // by hand — genuinely has no weight to send. The prompt says so in words when
  // it happens, rather than inventing a number to fill the field.
  grams: z.number().min(0).max(20_000).nullable(),
  label: z.string().max(200).nullable(),
});

export const refinementRequestSchema = z.strictObject({
  provider: z.enum(recognitionProviders).optional(),
  current: z.array(refinementItemSchema).max(64),
  note: z.string().trim().min(1).max(2_000),
});

export type RefinementRequest = z.infer<typeof refinementRequestSchema>;

export const mealRevisionSchema = z.strictObject({
  add: z.array(
    z.strictObject({
      group: z.enum(foodGroups),
      grams: z.number().min(0).max(20_000),
      label: z.string().max(200).nullable(),
      alternatives: z.array(z.enum(foodGroups)).max(3),
    }),
  ),
  revise: z.array(
    z.strictObject({
      index: z.number().int().min(1).max(64),
      group: z.enum(foodGroups),
      grams: z.number().min(0).max(20_000),
    }),
  ),
  remove: z.array(z.number().int().min(1).max(64)),
  notes: z.string().max(2_000).nullable(),
});

export type MealRevision = z.infer<typeof mealRevisionSchema>;

export function mealRevisionJsonSchema(): Record<string, unknown> {
  const schema = z.toJSONSchema(mealRevisionSchema, { target: "draft-07" });
  delete schema.$schema;
  return schema;
}

export const mealItemSchema = z.strictObject({
  id: z.string().uuid(),
  group: z.enum(foodGroups),
  // Stored, not requested. `portion` stays required because it is on every line
  // of every `events.jsonl` ever written and the log is append-only — v17 stops
  // asking a model for one, it does not rewrite history. New items carry the
  // schema default and score off `grams`.
  portion: z.enum(portions),
  label: z.string().max(200).nullable().optional(),
  modelAlternatives: z.array(z.enum(foodGroups)).nullable().optional(),
  // Events written before the alternatives contract still sync from devices
  // that have them in their append-only log. Accept, do not require.
  modelConfidence: z.number().min(0).max(1).nullable().optional(),
  // A strict object rejects what it does not name, and `MealItem` has carried
  // these three since dishes and grams landed. Without them here every weighed
  // meal 400s on sync — invisible until now only because the production Gemini
  // schema was never emitting a weight for one to carry.
  grams: z.number().min(0).max(20_000).nullable().optional(),
  servings: z.number().min(0).nullable().optional(),
  dish: z.string().max(120).nullable().optional(),
});

export const recognitionEvidenceSchema = z.strictObject({
  promptVersion: z.string().min(1).max(120),
  rawModelJSON: rawJsonSchema,
  initialItems: z.array(mealItemSchema).max(64),
  otherMealsVisible: z.boolean(),
});

export const mealEventDataSchema = z.strictObject({
  id: z.string().uuid(),
  eatenAt: z.number().int().nonnegative(),
  items: z.array(mealItemSchema).max(64),
  // `text` is a meal described in words with no photograph. Words alongside a
  // photo stay `photo`: the picture is the stronger evidence of what was there.
  source: z.enum(["photo", "manual", "recipe", "text"]),
  // Absent on entries logged before the switch existed; those were scored whole.
  share: z.enum(["whole", "part"]).nullable().optional(),
  // What the photo could not show, in the person's own words. Natural-language
  // labelling of exactly what recognition missed — a better input for clustering
  // weekly failures than any diff of the JSON.
  note: z.string().max(2_000).nullable().optional(),
  recognitionRating: z.enum(["good", "bad"]).nullable().optional(),
  // Links a meal card to the chat bubble it was parsed from. Accept, do not
  // require: this is a strict object, and an unknown key here 400s every sync
  // from a build that writes one — the grams/servings/dish failure again.
  messageID: z.string().uuid().nullable().optional(),
  photoHash: sha256Schema.nullable().optional(),
  modelConfidence: z.number().min(0).max(1).nullable().optional(),
  recognitionEvidence: recognitionEvidenceSchema.nullable().optional(),
  wasCorrected: z.boolean(),
});

export const loggedEventSchema = z.strictObject({
  id: z.string().uuid(),
  occurredAt: z.number().int().nonnegative(),
  recordedAt: z.number().int().nonnegative(),
  payload: z.strictObject({
    kind: z.enum(eventKinds),
    data: z.record(z.string(), z.unknown()),
  }),
});

export type LoggedEventInput = z.infer<typeof loggedEventSchema>;

export const ingestEventsRequestSchema = z.strictObject({
  deviceId: z.string().min(8).max(200),
  events: z.array(loggedEventSchema).min(1).max(500),
});

export type IngestEventsRequest = z.infer<typeof ingestEventsRequestSchema>;

export const eventListQuerySchema = z.strictObject({
  cursor: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

export const evalListQuerySchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

/**
 * A corpus image is deliberately not the media image again. It is a separate,
 * privacy-filtered render produced at save time; because cropping changes the
 * bytes, it has its own content hash while retaining the source photo hash for
 * provenance and deletion.
 */
export const corpusItemRequestSchema = z.strictObject({
  mealId: z.string().uuid(),
  sourcePhotoHash: sha256Schema,
  corpusHash: sha256Schema,
  mimeType: z.literal("image/jpeg"),
  imageBase64: z
    .string()
    .min(16)
    .max(8_000_000)
    .regex(/^[A-Za-z0-9+/]*={0,2}$/),
  consent: z.strictObject({
    granted: z.literal(true),
    policyVersion: z.string().min(1).max(120),
    capturedAt: z.number().int().nonnegative(),
  }),
  privacy: z.strictObject({
    cropMethod: z.string().min(1).max(120),
    facesExcluded: z.literal(true),
    otherMealsExcluded: z.literal(true),
  }),
});

export type CorpusItemRequest = z.infer<typeof corpusItemRequestSchema>;

export const mealDeleteDataSchema = z.strictObject({ mealID: z.string().uuid() });
