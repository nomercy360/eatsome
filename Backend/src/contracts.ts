import * as z from "zod";

export const foodKinds = [
  "rice",
  "pasta_noodles",
  "bread_flatbread",
  "cereal_porridge",
  "potato",
  "other_starchy_vegetable",
  "vegetable",
  "mushroom_seaweed",
  "fruit",
  "avocado_olive",
  "legume",
  "soy_product",
  "nuts_seeds",
  "beef",
  "pork",
  "lamb_game",
  "poultry",
  "processed_meat",
  "organ_meat",
  "fish",
  "shellfish",
  "egg",
  "milk",
  "yogurt",
  "cheese",
  "cream",
  "plant_milk",
  "oil",
  "butter_margarine",
  "mayonnaise_dressing",
  "sauce_condiment",
  "soup_broth",
  "sugar_honey_syrup",
  "chocolate_candy",
  "cake_cookie",
  "pastry",
  "frozen_dessert",
  "savory_snack",
  "nutrition_bar",
  "water",
  "coffee",
  "tea",
  "juice",
  "smoothie",
  "soft_sports_energy_drink",
  "beer",
  "wine",
  "spirit_cocktail",
  "supplement",
  "meal_replacement",
  "unknown",
] as const;

export const preparationMethods = [
  "raw",
  "boiled",
  "steamed",
  "baked",
  "roasted",
  "grilled",
  "pan_fried",
  "deep_fried",
  "smoked",
  "cured",
  "fermented",
  "dried",
] as const;

export const compositionHints = [
  "whole_grain",
  "refined_grain",
  "breaded",
  "sweetened",
  "unsweetened",
  "tomato_based",
  "soy_based",
  "dairy_based",
  "oil_based",
  "meat_based",
  "creamy",
] as const;

/**
 * TAXONOMY_BRIDGE_REMOVE_AFTER_V20_AUDIT: what a food group used to be called
 * on disk. New writes use `kind`; remove after the D1/reinstall audit.
 *
 * The taxonomy audit renamed two groups — `sofrito` became
 * `cooked_tomato_sauce`, `healthy_fats` became `plant_fats` — because both
 * carried a judgement in the name rather than describing food. Nothing
 * rewrites `events.jsonl`, so a phone syncing a two-year-old log still sends
 * the old spelling, and the server has to keep understanding it.
 *
 * Only the paths that receive *stored* data alias. What a model returns does
 * not: a model still answering `sofrito` after the prompt stopped asking for it
 * is a fault worth seeing, and silently accepting it is how a stale prompt
 * survives a deploy.
 */
export const legacyFoodKinds: Record<string, (typeof foodKinds)[number]> = {
  olive_oil: "oil",
  vegetable_oil: "oil",
  vegetables: "vegetable",
  legumes: "legume",
  nuts: "nuts_seeds",
  plant_fats: "avocado_olive",
  healthy_fats: "avocado_olive",
  whole_grains: "bread_flatbread",
  refined_grains: "bread_flatbread",
  whole_grain: "bread_flatbread",
  refined_grain: "bread_flatbread",
  white_meat: "poultry",
  red_meat: "beef",
  dairy: "milk",
  sweets: "chocolate_candy",
  sugary_drinks: "soft_sports_energy_drink",
  butter: "butter_margarine",
  butter_margarine_cream: "butter_margarine",
  alcohol: "beer",
  cooked_tomato_sauce: "sauce_condiment",
  sofrito: "sauce_condiment",
  potatoes: "potato",
  sauce: "sauce_condiment",
  other: "unknown",
};

export const storedFoodKind = z.preprocess(
  (value) =>
    typeof value === "string" && value in legacyFoodKinds ? legacyFoodKinds[value] : value,
  z.enum(foodKinds),
);

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
  "meta",
] as const;
export type RecognitionProvider = (typeof recognitionProviders)[number];
export const eventKinds = [
  "meal_logged",
  "meal_revised",
  "meal_deleted",
  "set_completed",
  "recipe_saved",
  "recipe_deleted",
  "message_sent",
  "message_deleted",
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

/**
 * Composition per 100 g of edible portion, as the food will be eaten.
 *
 * v20 asked only for weight and looked composition up in a table shipped with
 * the client. Measured against that table's own sourced rows the model
 * reproduces published composition at 0-3% median error, while the lookup left
 * 78% of logged grams unresolved because a free-text label rarely matches a
 * table key. Weight remains the load-bearing figure and the hard one.
 *
 * `sodium_mg` spells its unit out: every other field here is what its name
 * says, and a sodium field named for neither milligrams nor grams of salt is
 * how a factor of a thousand goes missing.
 */
export const compositionSchema = z.strictObject({
  protein: z.number().min(0).max(100),
  fat: z.number().min(0).max(100),
  carbohydrate: z.number().min(0).max(100),
  kcal: z.number().min(0).max(900),
  sodium_mg: z.number().min(0).max(40_000),
});

export type Composition = z.infer<typeof compositionSchema>;

/**
 * How far the four macronutrients may disagree with the energy figure before
 * the answer is treated as garbled.
 *
 * Atwater: protein and carbohydrate at 4 kcal/g, fat at 9. It is the one check
 * available with no table to compare against, and it is the replacement for the
 * unresolved-grams signal v20 used to make a bad answer visible. Measured on an
 * official Subway panel it came out at 2.3%; a tenth is loose enough for fibre,
 * polyols and rounding, and tight enough to catch a units error.
 */
export const ATWATER_TOLERANCE = 0.1;

export function atwaterDelta(value: Composition): number | null {
  if (value.kcal <= 0) return null;
  const fromMacros = value.protein * 4 + value.carbohydrate * 4 + value.fat * 9;
  return Math.abs(fromMacros - value.kcal) / value.kcal;
}

export const mealRecognitionItemSchema = z.strictObject({
  // Edible weight on the plate, absolute: everything of this ingredient that is
  // there, across every serving present. Nothing multiplies it by the dish's
  // count afterwards.
  //
  // Required, and the only quantity asked for. It was nullable while `portion`
  // stood behind it, and a fallback is exactly what let the production Gemini
  // schema omit the field for a month without anything failing — every answer
  // parsed, and every answer used the ladder grams had replaced. With
  // nothing behind it, a weightless answer is now a loud one.
  grams: z.number().min(0).max(20_000),
  // The whole identity now, and it must name exactly one food. 18% of the
  // distinct labels v20 failed to resolve named two ("ham and bacon",
  // "shredded cabbage and lettuce"), and a row that is two foods cannot be
  // priced as either.
  label: z.string().min(1).max(200),
  per_100g: compositionSchema,
  preparation: z.array(z.enum(preparationMethods)).max(4),
  // Uncertainty is a shortlist of rival groups, not a number. A model asked to
  // quantify its own certainty returns the same round value for every item on the
  // plate; asked what else the food could be, it answers about the food — and
  // the answer doubles as the one-tap correction in the client.
  alternatives: z
    .array(
      z.strictObject({
        label: z.string().min(1).max(200),
        // Priced, so the client can answer "honey or syrup?" without a second
        // call. Three composition blocks is a trivial addition to the response
        // and removes a round trip from the one question the sentence asks.
        per_100g: compositionSchema,
      }),
    )
    .max(3),
});

/**
 * One named thing on the tray, and what it is made of.
 *
 * `count` is how many servings of the dish are present, and it is a label
 * rather than a factor: the ingredients below already weigh every serving that
 * is there. The client's stepper rewrites those weights when the count is
 * corrected, so the number never multiplies anything during calculation.
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
});

export type MealRecognition = z.infer<typeof mealRecognitionSchema>;

/**
 * Which published figures a `published` nutrient came from.
 *
 * Kept because the scaling is the part that can be wrong. A Footlong priced by
 * doubling a Regular is a different claim from a figure printed for the item
 * ordered, and once the two are flattened into one number the difference cannot
 * be recovered. `scaleBasis` is the field that makes a wrong figure arguable.
 *
 * Nothing writes one today. Recognition is grounded in search, and a grounded
 * answer has no URL to keep — `generateContent` returns no grounding metadata
 * beside a response schema — so every figure it produces is `model`. The type
 * stays because storage has carried it since v21 and a stored meal that once
 * had a citation must still decode.
 */
export const sourceRefSchema = z.strictObject({
  url: z.string().min(1).max(2_000),
  fetchedAt: z.number().int().nonnegative(),
  market: z.string().max(8).nullable().optional(),
  scaleFactor: z.number().min(0).max(100).nullable().optional(),
  scaleBasis: z.string().max(64).nullable().optional(),
  productName: z.string().max(300).nullable().optional(),
});

export type SourceRef = z.infer<typeof sourceRefSchema>;

/**
 * What the client receives.
 *
 * v20 also carried a flattened `items` list, because meals predated dishes and
 * an old build read the flat list and ignored the rest. v21 stores dishes and
 * only dishes: two representations of one thing is how they come to disagree,
 * and there is no build left in the field that needs the other one.
 *
 * The one thing the server still does is normalise a panel to what the
 * container holds, which is arithmetic on a printed figure rather than an
 * estimate of anything.
 */
export const mealRecognitionPayloadSchema = mealRecognitionSchema;

export type MealRecognitionPayload = z.infer<typeof mealRecognitionPayloadSchema>;

export function normalizePanels(recognition: MealRecognition): MealRecognitionPayload {
  return {
    dishes: recognition.dishes.map((dish) => ({ ...dish, panel: panelPerContainer(dish.panel) })),
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
  label: z.string().min(1).max(200),
  grams: z.number().min(0).max(20_000),
});

export const refinementRequestSchema = z.strictObject({
  provider: z.enum(recognitionProviders).optional(),
  current: z.array(refinementItemSchema).max(64),
  note: z.string().trim().min(1).max(2_000),
});

export type RefinementRequest = z.infer<typeof refinementRequestSchema>;

/**
 * A correction, as a delta.
 *
 * `per_100g` is required on every add and every revise, and describes the food
 * AS IT NOW STANDS. Stored figures and editable rows can desync: a row renamed
 * from "chicken" to "fried chicken" whose numbers stayed behind is worse than an
 * uncorrected one, because it looks corrected.
 */
export const mealRevisionSchema = z.strictObject({
  add: z.array(
    z.strictObject({
      label: z.string().min(1).max(200),
      grams: z.number().min(0).max(20_000),
      per_100g: compositionSchema,
      preparation: z.array(z.enum(preparationMethods)).max(4),
      alternatives: z
        .array(
          z.strictObject({
            label: z.string().min(1).max(200),
            per_100g: compositionSchema,
          }),
        )
        .max(3),
    }),
  ),
  revise: z.array(
    z.strictObject({
      index: z.number().int().min(1).max(64),
      label: z.string().min(1).max(200),
      grams: z.number().min(0).max(20_000),
      per_100g: compositionSchema,
      preparation: z.array(z.enum(preparationMethods)).max(4),
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

export const nutrientSources = ["panel", "published", "model", "user"] as const;

const provenanceSchema = z.strictObject({
  protein: z.enum(nutrientSources),
  fat: z.enum(nutrientSources),
  carbohydrate: z.enum(nutrientSources),
  kcal: z.enum(nutrientSources),
  sodium: z.enum(nutrientSources),
});

/**
 * A stored food.
 *
 * No `kind`, no `portion`, no `servings`, no `resolution`, and no legacy
 * acceptance of any of them. v21 reads only v21: the migration rewrites the log
 * server-side and the client replaces its local copy, so there is nothing left
 * in the field writing the old shape. That is the whole of what makes this
 * schema free of the compatibility branches the last one accumulated.
 */
export const mealItemSchema = z.strictObject({
  id: z.string().uuid(),
  label: z.string().min(1).max(200),
  grams: z.number().min(0).max(20_000),
  per_100g: compositionSchema,
  provenance: provenanceSchema,
  preparation: z.array(z.enum(preparationMethods)).max(4).optional(),
  sourceRef: sourceRefSchema.nullable().optional(),
  alternatives: z
    .array(z.strictObject({ label: z.string().min(1).max(200), per_100g: compositionSchema }))
    .max(3)
    .optional(),
});

const storedNutritionPanelSchema = z.strictObject({
  protein: z.number().min(0).max(500).nullable().optional(),
  calories: z.number().min(0).max(5_000).nullable().optional(),
  fat: z.number().min(0).max(500).nullable().optional(),
  carbohydrate: z.number().min(0).max(1_000).nullable().optional(),
  salt: z.number().min(0).max(100).nullable().optional(),
  sodium: z.number().min(0).max(100).nullable().optional(),
  caffeine: z.number().min(0).max(2_000).nullable().optional(),
  basis: z.string().max(64).nullable().optional(),
  net_ml: z.number().min(0).max(10_000).nullable().optional(),
  net_g: z.number().min(0).max(10_000).nullable().optional(),
});

const storedMealDishSchema = z.strictObject({
  id: z.string().uuid(),
  /** Null for food that belongs to no named dish. */
  name: z.string().max(120).nullable().optional(),
  count: z.number().int().min(1).max(24),
  panel: storedNutritionPanelSchema.nullable().optional(),
  items: z.array(mealItemSchema).max(64),
});

export const recognitionEvidenceSchema = z.strictObject({
  promptVersion: z.string().min(1).max(120),
  model: z.string().max(120).nullable().optional(),
  rawModelJSON: rawJsonSchema,
  initialDishes: z.array(storedMealDishSchema).max(16),
});

/** The shape this event was written in. A reader that does not know a version
 * must refuse loudly rather than guess, which is the failure v20 shipped. */
export const MEAL_SCHEMA_VERSION = 21;

export const mealEventDataSchema = z.strictObject({
  id: z.string().uuid(),
  schemaVersion: z.literal(MEAL_SCHEMA_VERSION),
  eatenAt: z.number().int().nonnegative(),
  dishes: z.array(storedMealDishSchema).max(16),
  source: z.enum(["photo", "manual", "recipe", "text"]),
  share: z.enum(["whole", "part", "taste"]).nullable().optional(),
  note: z.string().max(2_000).nullable().optional(),
  recognitionRating: z.enum(["good", "bad"]).nullable().optional(),
  messageID: z.string().uuid().nullable().optional(),
  photoHash: sha256Schema.nullable().optional(),
  recognitionEvidence: recognitionEvidenceSchema.nullable().optional(),
  recognitionID: z.string().uuid().nullable().optional(),
  wasCorrected: z.boolean(),
  recipeID: z.string().uuid().nullable().optional(),
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

// ---------------------------------------------------------------------------
// Tables — your log, with friends in it.
//
// A post is a *copy* made at share time, never a reference into the sharer's
// log. The share sheet promises two things at the moment of the tap — "your
// olives never travel", and "what's in it" travels only if you switch it on —
// and a reference would have to re-derive both on every read, forever, against
// a `MealEntry` that keeps growing fields. A copy is a closed set: the three
// ingredient fields below and nothing else can ever leak, because nothing else
// is stored. The cost is drift — fix the meal later and the card your friends
// replied to stays as it was — and that is the correct behaviour for an
// utterance: a chat message does not rewrite itself after someone answers it.
// `mealId` stays on the post as provenance, not as a pointer to resolve.
//
// Account ids never appear in anything another member can read. Before real
// sign-in, an accountId IS the device id, and the device id is the only thing
// partitioning private logs — showing it to a tablemate would hand them the
// key to your entire log. Members are named by a per-table `memberId` minted
// at join, and by the display name they typed.
// ---------------------------------------------------------------------------

export const tableRoles = ["creator", "member"] as const;
export const postKinds = ["share", "message"] as const;
export const reactionKinds = ["olive", "heart"] as const;

/** Six friends is the design's whole point; 271 members is the anti-goal. */
export const TABLE_MAX_MEMBERS = 12;
export const TABLE_MAX_MEMBERSHIPS_PER_ACCOUNT = 32;

/** What the person is called at this table. Typed at join, because there is no
 *  profile to read it from yet — when sign-in lands it can prefill, and being
 *  per-membership means nobody has to build a profile system first. */
export const tableDisplayNameSchema = z.string().trim().min(1).max(40);
export const tableTitleSchema = z.string().trim().min(1).max(60);

export const tableVisibilitySchema = z.strictObject({
  photos: z.boolean().default(true),
  nutrition: z.boolean().default(false),
  bodyAndGoals: z.boolean().default(false),
});

/**
 * The whole redaction, as a schema: what one shared ingredient is allowed to
 * say. Group, weight, label — the same three fields `refinementItemSchema`
 * sends, because both describe food as it stands on a phone. No portion, no
 * alternatives, no evidence, and nothing derived: a friend's card answers
 * "what's in it", not "how did they do".
 */
export const postIngredientSchema = z.strictObject({
  kind: z.enum(foodKinds),
  grams: z.number().min(0).max(20_000).nullable(),
  label: z.string().max(200).nullable(),
});

export const createTableRequestSchema = z.strictObject({
  /** Client-generated UUIDv7, so a retried create is the same table. */
  id: z.string().uuid(),
  name: tableTitleSchema,
  displayName: tableDisplayNameSchema,
  visibility: tableVisibilitySchema.default({
    photos: true,
    nutrition: false,
    bodyAndGoals: false,
  }),
});

export const joinTableRequestSchema = z.strictObject({
  code: z.string().trim().min(6).max(20),
  displayName: tableDisplayNameSchema,
});

/**
 * One feed, two kinds of row. A `share` is a meal card: dish name, optional
 * photo, optional ingredients, optional caption. A `message` is words — the
 * composer at the bottom of the feed, and every reply. Replies are messages
 * with `replyToPostId` set, so threading is one nullable column rather than a
 * second table with its own pagination.
 *
 * A share names a photo by `photoHash` only. The tables API accepts no image
 * bytes at all — the server copies the already-stored recognition upload into
 * a table-owned object — so the one route where bytes enter R2 stays the
 * recognition path, with its limits and its consent story.
 */
export const createPostRequestSchema = z.discriminatedUnion("kind", [
  z.strictObject({
    /** Client-generated UUIDv7; a retried send is one post, not two. */
    id: z.string().uuid(),
    kind: z.literal("share"),
    /** Provenance. Which meal this was shared from; never resolved on read. */
    mealId: z.string().uuid(),
    dishName: z.string().trim().min(1).max(120),
    caption: z.string().max(2_000).nullable(),
    /** Null when "Show what's in it" was left off — absence is the redaction. */
    ingredients: z.array(postIngredientSchema).max(24).nullable(),
    /** Must already exist under the caller's own media; null for a text meal. */
    photoHash: sha256Schema.nullable(),
  }),
  z.strictObject({
    id: z.string().uuid(),
    kind: z.literal("message"),
    text: z.string().trim().min(1).max(2_000),
    /** A reply, when set. Must name a post in the same table. */
    replyToPostId: z.string().uuid().nullable(),
  }),
]);

export type CreatePostRequest = z.infer<typeof createPostRequestSchema>;

export const reactionRequestSchema = z.strictObject({
  postId: z.string().uuid(),
  kind: z.enum(reactionKinds),
  /** Toggling is idempotent both ways; a double-tap is one state, not an error. */
  on: z.boolean(),
});

/** Advances monotonically; sending an old seq cannot un-read anything. */
export const markReadRequestSchema = z.strictObject({
  seq: z.number().int().min(0),
});

/** A plate may carry one line and never a thread. Null removes it. */
export const updateTableNoteRequestSchema = z.strictObject({
  note: z.string().trim().max(2_000).nullable(),
});

export const tablesListQuerySchema = z.strictObject({
  /**
   * The caller's local start-of-day, in epoch millis, for "3 cooked today".
   * The server has no idea where the phone's midnight is — the caller supplies
   * the boundary explicitly. Absent means
   * `cookedToday` comes back null rather than counted against a made-up UTC day.
   */
  since: z.coerce.number().int().nonnegative().optional(),
});

export const tableFeedQuerySchema = z.strictObject({
  /** Seq of the oldest row already held; the page returns strictly older rows. */
  cursor: z.coerce.number().int().min(0).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100),
  since: z.coerce.number().int().nonnegative().optional(),
});

// --- Response shapes. Types rather than schemas: the server builds them, the
// --- Swift client mirrors them, and nothing needs to validate them twice.

export type TableMember = {
  /** Per-table public identity. Stable across renames; never the account id. */
  memberId: string;
  displayName: string;
  role: (typeof tableRoles)[number];
  isMe: boolean;
};

export type PostReactions = {
  kind: (typeof reactionKinds)[number];
  count: number;
  mine: boolean;
};

export type TablePost = {
  id: string;
  /** Server-assigned, per-table, monotonic. The feed's one total order — no
   *  device clock is trusted to sort someone else's dinner. */
  seq: number;
  kind: (typeof postKinds)[number];
  authorMemberId: string;
  authorName: string;
  mine: boolean;
  createdAt: number;
  /** share rows */
  mealId: string | null;
  dishName: string | null;
  caption: string | null;
  ingredients: z.infer<typeof postIngredientSchema>[] | null;
  /** True when GET /v1/tables/:id/media/:postId will stream a photo. */
  hasPhoto: boolean;
  /** message rows */
  text: string | null;
  replyToPostId: string | null;
  reactions: PostReactions[];
};

export type TableSummary = {
  id: string;
  name: string;
  members: TableMember[];
  /** Any member may invite — a table is a group of friends, not an org. */
  inviteCode: string;
  /** Link invites rotate and expire; the code remains for old clients and as
   *  the compact token encoded in the URL/QR. */
  inviteExpiresAt: number;
  /** The caller's own sharing boundary at this table. */
  visibility: z.infer<typeof tableVisibilitySchema>;
  /** Rows past the caller's read cursor, counted by the server against the
   *  same snapshot as everything else in the response. Never computed
   *  client-side from a partial page — that is how a badge undercounts while
   *  looking exact. */
  unreadCount: number;
  latestSeq: number;
  myLastReadSeq: number;
  /** Distinct members who shared a meal since the caller's `since` boundary;
   *  null when the caller did not say where their day starts. */
  cookedToday: number | null;
  /** Total plates since the caller's local midnight. */
  platesToday: number | null;
  /** A bounded, redacted strip for the Tables list. */
  recentPlates: {
    id: string;
    authorName: string;
    mine: boolean;
    createdAt: number;
    hasPhoto: boolean;
    reactionCount: number;
  }[];
  /** "Marta: recipe?? they look unreal" — for the slim row under the day. */
  latest: { authorName: string; text: string; createdAt: number } | null;
};

/**
 * Every tables response carries `asOf` — the moment the server counted. The
 * badge is a snapshot with a lag by construction (polling on open), and a
 * snapshot that states its time can be rendered as stale; one that does not is
 * a number pretending to be live. Same allergy, same cure, as `≥` on salt.
 */
export type TablesListResponse = { tables: TableSummary[]; asOf: number };

export type TableFeedResponse = {
  table: TableSummary;
  /** Newest first, `nextCursor` walks older. A reply whose parent fell off the
   *  page renders as a plain message until the parent is fetched. */
  posts: TablePost[];
  nextCursor: number | null;
  asOf: number;
};

export const identityProviders = ["apple", "google"] as const;

/**
 * What a phone posts to trade a provider's identity token for a session.
 *
 * The token is bounded at 8 KB because Apple's is roughly 1 KB and Google's
 * with a full profile is under 2 — anything an order of magnitude past that is
 * not a JWT and should be refused before it reaches a base64 decoder.
 *
 * `nonce` is the raw value the client generated for this sign-in, never the
 * hash it handed the provider. The server does the hashing, so a client that
 * sends the hash by mistake fails the check rather than passing it vacuously.
 */
export const signInRequestSchema = z.strictObject({
  provider: z.enum(identityProviders),
  identityToken: z.string().min(16).max(8192),
  nonce: z.string().min(8).max(200).optional(),
});

export type SignInRequest = z.infer<typeof signInRequestSchema>;
