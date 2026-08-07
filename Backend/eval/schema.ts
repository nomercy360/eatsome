import * as z from "zod";

/**
 * The candidate contract: the dataset's vocabulary, not the app's.
 *
 * The app ships a narrower taxonomy — no potatoes, no counted items, sauces
 * routed to whatever they are made of. The golden set was written from real
 * meals and says otherwise, and while the app is still being built the dataset
 * is the one to believe. So the eval asks the models for *this*, and whatever
 * survives the runs is what the app schema should become.
 *
 * Two consequences worth being explicit about:
 *
 * - a gap here is a real model failure, not a schema artefact. When the app
 *   could not express `potatoes`, scoring a potato as a miss blamed the prompt
 *   for something no prompt could fix; now the model is genuinely being asked.
 * - the numbers are not comparable with a run against the production contract.
 *   A different question was asked. That is what `promptVersion` and
 *   `schemaVersion` on every row are for.
 */
/**
 * v1  the dataset's vocabulary, asked for by name
 * v2  `alternatives` capped at three, which the prompt already said and the
 *     schema did not enforce — an unbounded list is how "at most three" becomes
 *     six on the one answer nobody reads closely
 */
/**
 * v3  dishes, not a flat list. A tray is dishes and a dish is ingredients, with
 *     the quantity on the dish — `count` of servings and `size` of one — and
 *     the ingredient saying only its share of a single serving. This replaces
 *     `measure: count | size`: everything now has both, which is what the app
 *     models. `dedup_note` largely retires with it, because two vegetable rows
 *     inside one bowl are no longer indistinguishable from two plates of veg.
 *     Adds `coffee` and `tea`, so caffeine has somewhere to come from.
 *
 *   v4 — `grams` on an ingredient, so a weighing prompt has somewhere to put an
 *     answer. Bumped because the fingerprint is what keeps runs comparable: a v3
 *     row could not carry a weight and a v4 row can, so pooling them would
 *     average a measurement with the absence of one.
 *
 *   v5 — grams-only, matching app prompt v17. `portion` and `size` are gone and
 *     `grams` is required rather than nullable. v4 asked for both quantities
 *     and let grams be null, which is exactly the shape that hid the production
 *     bug: the app's Gemini schema had no grams slot, every answer parsed on
 *     the ladder fallback, and the eval — asking a richer question than the app
 *     — reported numbers for a prompt nobody was running. The eval now asks
 *     the app's own quantity question; only the taxonomy stays wider.
 */
export const SCHEMA_VERSION = "eval-schema-v5-2026-08-07";

export const evalFoodGroups = [
  // Same idea as the app, dataset spelling.
  "refined_grain",
  "whole_grain",
  "white_meat",
  "red_meat",
  "processed_meat",
  "fish",
  "egg",
  "dairy",
  "legumes",
  "vegetables",
  "fruit",
  "nuts",
  "sweets",
  "pastry",
  "olive_oil",
  "sofrito",
  "sugary_drinks",
  "butter_margarine_cream",
  "healthy_fats",
  // Present in the dataset and missing from the app. These are the migration
  // list: what the eval decides, the app inherits.
  "potatoes",
  "sauce",
  // Caffeine has no home without these: a latte is filed as dairy today, which
  // captures the milk and loses the only part with a daily threshold, and a
  // black coffee produces nothing at all.
  "coffee",
  "tea",
  "alcohol",
  "juice",
  "smoothie",
  "plant_milk",
  "other",
] as const;

export const evalFlags = [
  "fried",
  "breaded",
  "raw_ingredient",
  "added_sugar",
  "opaque_packaging",
  // A wrap whose filling is not visible. Without it the model has no way to say
  // "I can see bread and cannot see what is in it", and the only alternatives
  // are inventing a filling or omitting the item.
  "filling_unknown",
] as const;

export const mealStatuses = [
  "eaten",
  "ate_part",
  "shared_plate",
  "not_yet_eaten",
  "not_a_meal",
] as const;

/**
 * Discrete foods are counted, not sized. A third of the golden items are — two
 * eggs, three prawns, one sachet — and it is the measure that makes protein
 * estimable at all, since its sources are the countable ones.
 */
export const evalItemSchema = z.strictObject({
  name: z.string().max(200),
  group: z.enum(evalFoodGroups),
  alternatives: z.array(z.enum(evalFoodGroups)).max(3),
  /**
   * Edible weight on the plate, absolute — everything of this ingredient that
   * is there, across every serving present.
   *
   * Required, and the only quantity. It was nullable with a `portion` fallback
   * through v4, and a fallback for a required measurement is a way to not
   * notice it is missing — the scorer silently graded the ladder and the
   * report said the weight was measured.
   */
  grams: z.number().min(0).max(20_000),
  flags: z.array(z.enum(evalFlags)),
});

/**
 * Figures printed on packaging, transcribed. Null when nothing is printed,
 * which is almost all food. Every field nullable on its own: reading protein
 * and not sodium is a normal answer, and a figure that cannot be read must be
 * able to come back absent rather than plausible.
 */
export const evalPanelSchema = z.strictObject({
  protein: z.number().min(0).max(500).nullable(),
  calories: z.number().min(0).max(5_000).nullable(),
  fat: z.number().min(0).max(500).nullable(),
  carbohydrate: z.number().min(0).max(1_000).nullable(),
  sodium: z.number().min(0).max(100).nullable(),
  caffeine: z.number().min(0).max(2_000).nullable(),
});

export const evalDishSchema = z.strictObject({
  name: z.string().max(200),
  /**
   * Servings of this dish present. Three slices of bread is one dish, count 3.
   * A label on the weights, never a multiplier of them.
   */
  count: z.number().int().min(1).max(99),
  panel: evalPanelSchema.nullable(),
  ingredients: z.array(evalItemSchema).max(24),
});

export const evalRecognitionSchema = z.strictObject({
  meal_status: z.enum(mealStatuses),
  dishes: z.array(evalDishSchema).max(24),
  other_meals_visible: z.boolean(),
  notes: z.string().max(2_000).nullable(),
});

export type EvalRecognition = z.infer<typeof evalRecognitionSchema>;

export function evalJsonSchema(): Record<string, unknown> {
  const schema = z.toJSONSchema(evalRecognitionSchema, { target: "draft-07" });
  delete schema.$schema;
  return schema;
}

/** Gemini's OpenAPI subset: no additionalProperties, nullable as a flag. */
export function evalGeminiSchema(): Record<string, unknown> {
  const group = { type: "STRING", enum: [...evalFoodGroups] };
  return {
    type: "OBJECT",
    propertyOrdering: ["meal_status", "dishes", "other_meals_visible", "notes"],
    required: ["meal_status", "dishes", "other_meals_visible", "notes"],
    properties: {
      meal_status: { type: "STRING", enum: [...mealStatuses] },
      dishes: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["name", "count", "panel", "ingredients"],
          required: ["name", "count", "panel", "ingredients"],
          properties: {
            name: { type: "STRING" },
            count: { type: "INTEGER" },
            panel: {
              type: "OBJECT",
              nullable: true,
              propertyOrdering: [
                "protein",
                "calories",
                "fat",
                "carbohydrate",
                "sodium",
                "caffeine",
              ],
              required: ["protein", "calories", "fat", "carbohydrate", "sodium", "caffeine"],
              properties: {
                protein: { type: "NUMBER", nullable: true },
                calories: { type: "NUMBER", nullable: true },
                fat: { type: "NUMBER", nullable: true },
                carbohydrate: { type: "NUMBER", nullable: true },
                sodium: { type: "NUMBER", nullable: true },
                caffeine: { type: "NUMBER", nullable: true },
              },
            },
            ingredients: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                propertyOrdering: ["name", "group", "alternatives", "grams", "flags"],
                required: ["name", "group", "alternatives", "grams", "flags"],
                properties: {
                  name: { type: "STRING" },
                  group,
                  alternatives: { type: "ARRAY", items: group, maxItems: 3 },
                  // Required and not nullable — Gemini emits exactly what a
                  // schema names, which is how the app shipped a weighing
                  // prompt with no weights for a month.
                  grams: { type: "NUMBER" },
                  flags: { type: "ARRAY", items: { type: "STRING", enum: [...evalFlags] } },
                },
              },
            },
          },
        },
      },
      other_meals_visible: { type: "BOOLEAN" },
      notes: { type: "STRING", nullable: true },
    },
  };
}
