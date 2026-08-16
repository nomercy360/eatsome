import * as z from "zod";

/**
 * The wire, in one file.
 *
 * Two shapes live here and they are deliberately not the same shape:
 *
 *   - what the **model** returns (`mealRecognitionSchema`, `mealRevisionSchema`),
 *     which is what the prompt and the provider schema in `worker/ai/gemini.ts`
 *     are held to; and
 *   - what the **phone** stores and uploads (`mealEventDataSchema`), which is
 *     `MealEntry` in `Core/Sources/EatsomeCore/Model/Meal.swift`, field for
 *     field, spelled the way Swift's `CodingKeys` spell it.
 *
 * The second one is a mirror and has no freedom. If it drifts, `projectMealMedia`
 * stops recognising meals, `meal_media` never gets a row, and the orphan sweep
 * deletes photographs of meals people actually saved. That failure is silent by
 * construction, which is why the ingest path now refuses an unparseable meal
 * loudly instead of skipping it.
 */

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

/** The five kinds this build understands, and the three it projects. */
export const eventKinds = [
  "meal_logged",
  "meal_revised",
  "meal_deleted",
  "message_sent",
  "message_deleted",
] as const;

/**
 * The kind of a stored event: any well-formed name.
 *
 * Deliberately not `z.enum(eventKinds)`, and the reason is the pull endpoint.
 * The phone keeps an event it does not understand byte for byte
 * (`EventPayload.unrecognized`) and uploads it whole; the mirror hands it back
 * to the account's other phones as the same bytes. Both halves only work if the
 * server never has an opinion about the name — refuse one kind here and a batch
 * containing it 400s in full, so a phone that has not updated stops syncing the
 * moment any phone does, and `id` alone can no longer be what makes two logs
 * converge.
 *
 * What is still refused is a name that is not a name. And a meal *is* read,
 * strictly, because the server has one job that depends on understanding one —
 * see `mealEventDataSchema`.
 */
export const storedEventKindSchema = z
  .string()
  .regex(/^[a-z][a-z0-9_]{1,63}$/, "Expected a snake_case event kind.");

export const sha256Schema = z
  .string()
  .regex(/^[a-f0-9]{64}$/i, "Expected a 64-character SHA-256 hex digest.");

/** Swift encodes a `UUID` in upper case; the regex behind `z.uuid()` is
 *  case-insensitive, so both spellings of the same id parse. */
const uuidSchema = z.uuid();

// ---------------------------------------------------------------------------
// Composition — the seven figures, and the check that they agree with themselves
// ---------------------------------------------------------------------------

/**
 * Composition per 100 g of edible portion, as the food will be eaten.
 *
 * Seven figures, all required, because zero has to be a statement the model made
 * about the food rather than a default the parser filled in. `alcohol` is what
 * lets the Atwater check below reconcile a beer — ethanol is 7 kcal/g and its
 * energy is already inside `kcal` — and `caffeine_mg` is what gives a filter
 * coffee any caffeine at all without a printed label in the photograph.
 *
 * `sodium_mg` and `caffeine_mg` spell their unit out. Every other field here is
 * what its name says, and a field named for neither milligrams nor grams is how
 * a factor of a thousand goes missing.
 *
 * Mirrors `Nutrients` in `EatsomeCore`, field for field and key for key.
 */
export const compositionSchema = z.strictObject({
  protein: z.number().min(0).max(100),
  fat: z.number().min(0).max(100),
  carbohydrate: z.number().min(0).max(100),
  kcal: z.number().min(0).max(900),
  sodium_mg: z.number().min(0).max(40_000),
  /** Grams of ethanol per 100 g. Spirits sit near 40; nothing edible exceeds 100. */
  alcohol: z.number().min(0).max(100),
  /** Milligrams per 100 g. Espresso is ~200, matcha powder ~3 000, and the cap
   *  admits pure caffeine powder without admitting a units slip. */
  caffeine_mg: z.number().min(0).max(100_000),
});

export type Composition = z.infer<typeof compositionSchema>;

/**
 * How far the macronutrients may disagree with the energy figure before the
 * answer is treated as garbled.
 *
 * Atwater: protein and carbohydrate at 4 kcal/g, fat at 9, ethanol at 7. It is
 * the only check available with no table to compare against, and it is the loud
 * failure this design relies on. Measured on an official Subway panel it came
 * out at 2.3%; a tenth is loose enough for fibre, polyols and rounding, and
 * tight enough to catch a units error.
 *
 * The factors mirror `Nutrients.energyPerGram` in `EatsomeCore` exactly.
 */
export const ATWATER_TOLERANCE = 0.1;

export const ENERGY_PER_GRAM = { protein: 4, carbohydrate: 4, fat: 9, alcohol: 7 } as const;

export function atwaterEnergy(value: Composition): number {
  return (
    value.protein * ENERGY_PER_GRAM.protein +
    value.carbohydrate * ENERGY_PER_GRAM.carbohydrate +
    value.fat * ENERGY_PER_GRAM.fat +
    value.alcohol * ENERGY_PER_GRAM.alcohol
  );
}

/** Nil when there is no energy to check against: zero is an absence, not a disagreement. */
export function atwaterDelta(value: Composition): number | null {
  if (value.kcal <= 0) return null;
  return Math.abs(atwaterEnergy(value) - value.kcal) / value.kcal;
}

// ---------------------------------------------------------------------------
// What the model returns
// ---------------------------------------------------------------------------

/**
 * A priced *and weighed* rival for a food the model was not sure about.
 *
 * One shape, used by recognition, by a correction's `add`, and by the stored
 * item. Weight is the half that is easy to leave out and the half that matters:
 * a rival is rarely the same size as the first answer — a tuna sub is not a
 * turkey sub — so a swap that changes composition and keeps the old weight
 * produces a figure that looks chosen and is not.
 */
const alternativeShape = {
  label: z.string().min(1).max(200),
  per_100g: compositionSchema,
  grams: z.number().min(0).max(20_000),
};

export const alternativeSchema = z.strictObject(alternativeShape);

/**
 * A fork: a choice the input left open that moves one row's figures — which
 * size, which milk, which drink is in the cup — as a set of complete priced
 * answers for the same food, one of them being what the row already assumes.
 *
 * Generic on purpose. It replaced `sizes`, which could say Regular/Footlong
 * and nothing else; measured on 14 inputs (`eval/forks-poc.md`) the model
 * put Coke/Diet Coke/Sprite (Δ220 kcal) and whole/oat/non-fat milk (Δ91) in
 * the same shape, priced each option in full, and marked the row's own answer
 * `chosen` 81 times out of 81. An option is not a multiplier: a 6-inch and a
 * Footlong are two products with their own figures, so choosing one
 * *replaces* the row's weight and composition the way choosing an alternative
 * replaces its name.
 */
export const forkEvidence = ["stated", "seen", "assumed"] as const;

const forkOptionShape = {
  /** In the words the person would use, in the market's language: "Footlong",
   *  "並盛", "Grande", "oat milk", "Coke Zero". */
  label: z.string().min(1).max(60),
  grams: z.number().min(0).max(20_000),
  per_100g: compositionSchema,
  /** True on the one option the row's own grams and per_100g already assume. */
  chosen: z.boolean(),
};

/** `basis` says whether somebody printed this option's figures or whether they
 *  are arithmetic on another one. Subway publishes the Regular and everyone
 *  doubles it, which makes a Footlong the option most likely to be wrong. The
 *  stored form drops it: it is a fact about the answer, not about the plate. */
const forkOptionSchema = z.strictObject({
  ...forkOptionShape,
  basis: z.enum(["published", "derived"]),
});

const forkShape = {
  /** One or two lowercase words: "size", "milk", "drink". Rendered, never
   *  branched on — an enum here would make a milk question wait for a release. */
  axis: z.string().min(1).max(30),
  /**
   * What decided the chosen option. `stated`: the person's words name it.
   * `seen`: the photograph shows it. `assumed`: nothing did, and the model took
   * the usual one. Only an `assumed` fork is a question for the person; the
   * other two are kept as priced options for the pick sheet. Asked to keep the
   * fork out of the answer when the input had settled it, the model could not
   * (3 of 4 runs of "grande oat milk latte" still offered sizes); asked to say
   * which it was, it was right 16 of 16.
   */
  chosen_from: z.enum(forkEvidence),
};

/** Exactly one option is chosen. Required of the stored form, which the app
 *  writes; the model's answer is *settled* into it by `settleForks` rather
 *  than refused, because a fork it left without a default (seen once in five
 *  on a cappuccino's milk) is not a reason to lose the meal. Two to six
 *  options: one is not a choice, and Yoshinoya sells a gyudon in six — 小盛
 *  through 超特盛. */
const oneChosen = (options: Array<{ chosen: boolean }>) =>
  options.filter((option) => option.chosen).length === 1;

const forkSchema = z.strictObject({
  ...forkShape,
  options: z.array(forkOptionSchema).min(2).max(6),
});

export const mealRecognitionItemSchema = z.strictObject({
  // Edible weight on the plate, absolute: everything of this ingredient that is
  // there, across every serving present. Nothing multiplies it by the dish's
  // count afterwards.
  //
  // Required, and the only quantity asked for. It was nullable once, behind a
  // portion ladder, and a fallback is exactly what let the Gemini schema omit
  // the field for a month without anything failing.
  grams: z.number().min(0).max(20_000),
  // The whole identity. It must name exactly one food: a row that is two foods
  // ("ham and bacon") cannot be priced as either.
  label: z.string().min(1).max(200),
  per_100g: compositionSchema,
  preparation: z.array(z.enum(preparationMethods)).max(4),
  // Uncertainty is a shortlist of priced rivals, not a number. A model asked to
  // quantify its own certainty returns the same round value for everything on
  // the plate; asked what else the food could be, it answers about the food —
  // and the answer doubles as the one-tap correction in the client.
  alternatives: z.array(alternativeSchema).max(3),
  /**
   * The chain or manufacturer whose menu item this row *is*.
   *
   * Not a label on the food, a statement about how it is sold: null for
   * everything cooked, served loose, or added on top of a menu item. That is
   * what the client needs, because the two kinds of food take different
   * corrections. A bowl of rice is corrected in grams; a Big Mac cannot be —
   * you did not eat 217 g of Big Mac, you ate one.
   */
  brand: z.string().max(120).nullable(),
  /** The choices the input left open on this row, each a set of priced
   *  answers. Empty is the normal case: nothing on a home plate or a canteen
   *  tray, nothing on food that comes one way. Three, most consequential
   *  first. */
  forks: z.array(forkSchema).max(3),
});

/**
 * A nutrition panel transcribed off packaging, for the unit the label names.
 *
 * Read, never estimated — that distinction is the whole justification for the
 * field existing. Every figure is nullable because an unreadable one must be
 * able to come back absent: a fabricated number stored in the one place
 * reserved for confirmed values is worse than no value at all.
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
  /** Grams of alcohol, when a label prints it. Most print ABV instead, which is
   *  not this field: a percentage by volume is not grams in the container. */
  alcohol: z.number().min(0).max(500).nullable(),
  /** Milligrams, as printed on an energy drink. Never an estimate — that is
   *  `caffeine_mg` on the composition block. */
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
  "alcohol",
  "caffeine",
] as const;

/** Salt is sodium chloride: 2.54 g of salt carries 1 g of sodium. */
const SODIUM_PER_SALT = 1 / 2.54;

/**
 * The panel as one container's worth, which is what a person consumed.
 *
 * The multiplication happens here rather than in the prompt because a model
 * that does arithmetic does it invisibly — the same freedom that turned 0.1 g
 * of salt into "~0.04 g sodium" unasked. Transcribed facts in, deterministic
 * maths out, and a panel that cannot be scaled keeps its figures and says so
 * through `basis` rather than pretending to be per-container.
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
  /** How many servings are present. A label on the weights, never a multiplier
   *  of them: the ingredients below already weigh every serving that is there. */
  count: z.number().int().min(1).max(24),
  ingredients: z.array(mealRecognitionItemSchema).max(24),
  /** Null for almost all food, which has nothing printed on it. */
  panel: nutritionPanelSchema.nullable(),
});

/**
 * What the model returns: the dishes it read, and nothing else.
 *
 * Empty `dishes` is a message that described no food, and it is what the
 * *Couldn't read it* screen is for. No daily totals, no scores, no confidence.
 */
export const mealRecognitionSchema = z.strictObject({
  dishes: z.array(mealDishSchema).max(16),
});

export type MealRecognition = z.infer<typeof mealRecognitionSchema>;

export function mealRecognitionJsonSchema(): Record<string, unknown> {
  const schema = z.toJSONSchema(mealRecognitionSchema, { target: "draft-07" });
  delete schema.$schema;
  return schema;
}

/** The panel normalised to what the container holds — arithmetic on a printed
 *  figure rather than an estimate of anything — and every fork settled on one
 *  chosen option. The two things the server changes about a model answer. */
export function normalizePanels(recognition: MealRecognition): MealRecognition {
  return {
    ...recognition,
    dishes: recognition.dishes.map((dish) => ({
      ...dish,
      panel: panelPerContainer(dish.panel),
      ingredients: dish.ingredients.map((item) => ({ ...item, forks: settleForks(item) })),
    })),
  };
}

/** How far an option's whole-row energy may sit from the row's own before it
 *  cannot be the row's answer: the Atwater tolerance, for the same reason. */
const FORK_MATCH_TOLERANCE = ATWATER_TOLERANCE;

/**
 * Every fork on a row with exactly one chosen option: the one the row's own
 * figures assume.
 *
 * The model marks it 81 times in 81 on branded food and then, once in five,
 * hands back a cappuccino's milk with nothing chosen. A fork with no default is
 * a set of chips none of which is lit, which says the figures came from
 * nowhere; a fork with two is the model disagreeing with itself. Either is
 * settled by arithmetic on what is already there: the option whose whole-row
 * energy is nearest the row's own is the answer, and it is confirmed only if
 * it is within tolerance. A fork none of whose options describes this row is
 * dropped — its numbers were priced for something else, and offering them
 * would be the rename-cannot-re-price failure.
 */
export function settleForks(item: {
  grams: number;
  per_100g: Composition;
  forks: MealRecognition["dishes"][number]["ingredients"][number]["forks"];
}): MealRecognition["dishes"][number]["ingredients"][number]["forks"] {
  const rowKcal = (item.grams * item.per_100g.kcal) / 100;
  return item.forks.flatMap((fork) => {
    if (oneChosen(fork.options)) return [fork];
    const distance = (option: (typeof fork.options)[number]) =>
      Math.abs((option.grams * option.per_100g.kcal) / 100 - rowKcal);
    const nearest = fork.options.reduce((best, option) =>
      distance(option) < distance(best) ? option : best,
    );
    // Within tolerance of the row, or of nothing at all — a zero-energy row
    // has no distance to be within, so the nearest is taken as read.
    const fits = rowKcal <= 0 || distance(nearest) / rowKcal <= FORK_MATCH_TOLERANCE;
    if (!fits) return [];
    return [
      {
        ...fork,
        options: fork.options.map((option) => ({ ...option, chosen: option === nearest })),
      },
    ];
  });
}

/**
 * Every food in an answer whose own figures do not add up, with the size of the
 * disagreement.
 *
 * The loud failure, as a function. With a composition table a bad answer showed
 * up as weight that resolved to nothing; with composition stored on the row it
 * would be silent, so this is what the recognition path logs on.
 */
export function atwaterFailures(
  recognition: MealRecognition,
): Array<{ dish: string; label: string; delta: number }> {
  const failures: Array<{ dish: string; label: string; delta: number }> = [];
  for (const dish of recognition.dishes) {
    for (const item of dish.ingredients) {
      const delta = atwaterDelta(item.per_100g);
      if (delta !== null && delta > ATWATER_TOLERANCE) {
        failures.push({ dish: dish.name, label: item.label, delta });
      }
    }
  }
  return failures;
}

// ---------------------------------------------------------------------------
// What the phone asks for
// ---------------------------------------------------------------------------

/**
 * A logged meal arrives as a photograph, as the person's own words — typed or
 * dictated — or as both at once, so the image is optional. It is three fields
 * that only mean anything together, which is why they are optional as a unit: a
 * request carrying some of them is malformed, not text-only.
 *
 * `said` is deliberately not `note`. The note is a supplement to a photograph —
 * "what the photo cannot show", evidence attached to an image the model still
 * reads for itself — while `said` IS the input: for a text-only meal it is
 * everything the model has. The prompt frames the two differently, and folding
 * them into one field would either promote every note to a description or
 * demote every description to a footnote.
 */
export const recognitionRequestSchema = z
  .strictObject({
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

export const refinementItemSchema = z.strictObject({
  label: z.string().min(1).max(200),
  grams: z.number().min(0).max(20_000),
});

export const refinementDishSchema = z.strictObject({
  name: z.string().min(1).max(120),
  count: z.number().int().min(1).max(24),
  /** 1-based positions in `current`, so the model can see which foods belong to
   *  each count without duplicating the food payload. */
  item_indices: z.array(z.number().int().min(1).max(64)).max(64),
});

export const refinementRequestSchema = z.strictObject({
  current: z.array(refinementItemSchema).max(64),
  dishes: z.array(refinementDishSchema).max(16),
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
      alternatives: z.array(alternativeSchema).max(3),
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
  dish_counts: z.array(
    z.strictObject({
      index: z.number().int().min(1).max(16),
      count: z.number().int().min(1).max(24),
    }),
  ),
  dish_names: z.array(
    z.strictObject({
      index: z.number().int().min(1).max(16),
      name: z.string().min(1).max(120),
    }),
  ),
  remove: z.array(z.number().int().min(1).max(64)),
  notes: z.string().max(2_000).nullable(),
});

export type MealRevision = z.infer<typeof mealRevisionSchema>;

// ---------------------------------------------------------------------------
// What the phone stores — `MealEntry` in EatsomeCore, mirrored
// ---------------------------------------------------------------------------

/**
 * Where one figure came from. No `table` case because there is no table, and no
 * `published` case because nothing writes one: grounded recognition returns
 * better numbers than a fetched page and returns them with no citation, so a
 * searched answer is a better estimate and the app says "estimated" about it.
 */
export const nutrientSources = ["panel", "model", "user"] as const;

/** Per figure rather than per item, because a panel is routinely partial: a
 *  carton printing protein and energy but no sodium contributes two read
 *  figures and five from the model. Keys as `NutrientProvenance` spells them —
 *  `sodium`, not `sodium_mg`, because this names a figure and not a unit. */
const provenanceSchema = z.strictObject({
  protein: z.enum(nutrientSources),
  fat: z.enum(nutrientSources),
  carbohydrate: z.enum(nutrientSources),
  kcal: z.enum(nutrientSources),
  sodium: z.enum(nutrientSources),
  alcohol: z.enum(nutrientSources),
  caffeine: z.enum(nutrientSources),
});

/** `Nutrients` as a whole-meal total: the same seven keys, without the per-100 g
 *  ceilings, for a figure the person typed in themselves. */
const nutrientTotalSchema = z.strictObject({
  protein: z.number().min(0).max(10_000),
  fat: z.number().min(0).max(10_000),
  carbohydrate: z.number().min(0).max(20_000),
  kcal: z.number().min(0).max(100_000),
  sodium_mg: z.number().min(0).max(1_000_000),
  alcohol: z.number().min(0).max(10_000),
  caffeine_mg: z.number().min(0).max(1_000_000),
});

/** `MealItem`. Its arrays are non-optional in Swift, so they always arrive;
 *  `brand` is the one field the encoder omits when it is nil. */
export const mealItemSchema = z.strictObject({
  id: uuidSchema,
  label: z.string().min(1).max(200),
  grams: z.number().min(0).max(20_000),
  per_100g: compositionSchema,
  provenance: provenanceSchema,
  preparation: z.array(z.enum(preparationMethods)).max(4),
  alternatives: z.array(z.strictObject({ id: uuidSchema, ...alternativeShape })).max(3),
  brand: z.string().max(120).nullable().optional(),
  forks: z
    .array(
      z.strictObject({
        id: uuidSchema,
        ...forkShape,
        options: z
          .array(z.strictObject({ id: uuidSchema, ...forkOptionShape }))
          .min(2)
          .max(6)
          .refine(oneChosen, { message: "exactly one option must be chosen" }),
      }),
    )
    .max(3),
});

/** `NutritionPanel` as stored: already scaled to the dish, so no `basis` and no
 *  net contents, and `kcal` rather than the label's word `calories`. */
const storedPanelSchema = z.strictObject({
  kcal: z.number().min(0).max(100_000).nullable().optional(),
  protein: z.number().min(0).max(10_000).nullable().optional(),
  fat: z.number().min(0).max(10_000).nullable().optional(),
  carbohydrate: z.number().min(0).max(20_000).nullable().optional(),
  salt: z.number().min(0).max(1_000).nullable().optional(),
  sodium: z.number().min(0).max(1_000).nullable().optional(),
  alcohol: z.number().min(0).max(10_000).nullable().optional(),
  caffeine: z.number().min(0).max(100_000).nullable().optional(),
});

const mealShares = ["whole", "part", "taste"] as const;

/** `MealDish`. `name` and `share` are omitted by the encoder when nil. */
const storedMealDishSchema = z.strictObject({
  id: uuidSchema,
  name: z.string().max(120).nullable().optional(),
  count: z.number().int().min(1).max(24),
  share: z.enum(mealShares).nullable().optional(),
  panel: storedPanelSchema.nullable().optional(),
  items: z.array(mealItemSchema).max(64),
});

/**
 * The shape this event was written in.
 *
 * A reader that does not know a version must refuse loudly rather than guess.
 * Version one stored the retired `sizes` picker; version two stores `forks`.
 */
export const MEAL_SCHEMA_VERSION = 2;

/**
 * `MealEntry`, exactly.
 *
 * Strict on purpose. A field the app writes and this schema does not name is a
 * 400 on every sync from that build, which is the correct outcome: the
 * alternative is `projectMealMedia` quietly skipping the meal and the orphan
 * sweep deleting its photograph a day later.
 */
export const mealEventDataSchema = z.strictObject({
  id: uuidSchema,
  schemaVersion: z.literal(MEAL_SCHEMA_VERSION),
  eatenAt: z.number().int().nonnegative(),
  dishes: z.array(storedMealDishSchema).max(16),
  source: z.enum(["photo", "text", "manual"]),
  photoHash: sha256Schema.nullable().optional(),
  /** What the photograph could not show, sent to the model with the image. */
  note: z.string().max(2_000).nullable().optional(),
  /** Something written afterwards, which is input to nothing. */
  personalNote: z.string().max(2_000).nullable().optional(),
  share: z.enum(mealShares).nullable().optional(),
  nutritionOverride: nutrientTotalSchema.nullable().optional(),
  wasCorrected: z.boolean(),
  messageID: uuidSchema.nullable().optional(),
});

export type MealEventData = z.infer<typeof mealEventDataSchema>;

/**
 * The only projection the Worker needs from historical version-one meals.
 *
 * Their nutrition remains opaque event data. The Worker only needs the meal id
 * and photograph hash to keep media alive, so retired fields such as `sizes`
 * are intentionally neither named nor converted here. `z.object` strips those
 * unknown fields after validating the metadata the projection actually uses.
 */
export const legacyMealMediaProjectionSchema = z.object({
  id: uuidSchema,
  schemaVersion: z.literal(1),
  photoHash: sha256Schema.nullable().optional(),
});

export type MealMediaProjection = Pick<MealEventData, "id" | "photoHash"> & {
  schemaVersion: 1 | typeof MEAL_SCHEMA_VERSION;
};

export const mealDeleteDataSchema = z.strictObject({ mealID: uuidSchema });

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

export const loggedEventSchema = z.strictObject({
  id: uuidSchema,
  occurredAt: z.number().int().nonnegative(),
  recordedAt: z.number().int().nonnegative(),
  payload: z.strictObject({
    kind: storedEventKindSchema,
    data: z.record(z.string(), z.unknown()),
  }),
});

export type LoggedEventInput = z.infer<typeof loggedEventSchema>;

export const ingestEventsRequestSchema = z.strictObject({
  deviceId: z.string().min(8).max(200),
  events: z.array(loggedEventSchema).min(1).max(500),
});

export type IngestEventsRequest = z.infer<typeof ingestEventsRequestSchema>;

/**
 * A page of the account's log, oldest first.
 *
 * Sync is two-way and merges by id, which it can be because an event is
 * immutable: the same id is always the same record, so a union needs no
 * conflict policy and no clock anyone trusts. That replaced a
 * phone-authoritative reconcile — the phone uploaded its whole log and then
 * sent every id it held so the server could delete the rest — which made the
 * *last device to sync* the definition of the account's history, and quietly
 * deleted the other phone's meals to get there.
 *
 * `after` is the opaque cursor from the previous page, and the order is
 * `(recordedAt, id)`: `recordedAt` is server-visible epoch millis and the id is
 * a UUIDv7 that breaks ties the same way on every page, so the pair is a total
 * order over the stored rows and paging cannot skip or repeat one.
 */
export const eventPullQuerySchema = z.strictObject({
  after: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

export type EventPullQuery = z.infer<typeof eventPullQuerySchema>;

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/** Apple only. The Google half was implemented server-side and never had a
 *  client; an identity provider with no sign-in button is a verification path
 *  nobody exercises, which is the worst kind to keep. */
export const identityProviders = ["apple"] as const;

/**
 * What a phone posts to trade a provider's identity token for a session.
 *
 * The token is bounded at 8 KB because Apple's is roughly 1 KB — anything an
 * order of magnitude past that is not a JWT and should be refused before it
 * reaches a base64 decoder.
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
