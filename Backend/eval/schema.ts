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
 */
export const SCHEMA_VERSION = "eval-schema-v3-2026-08-06";

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
  /** This ingredient's share of ONE serving of the dish, never of the whole. */
  portion: z.enum(["S", "M", "L"]),
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
  /** Servings of this dish present. Three slices of bread is one dish, count 3. */
  count: z.number().int().min(1).max(99),
  /** How big ONE serving is, never how many. */
  size: z.enum(["S", "M", "L"]),
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
          propertyOrdering: ["name", "count", "size", "panel", "ingredients"],
          required: ["name", "count", "size", "panel", "ingredients"],
          properties: {
            name: { type: "STRING" },
            count: { type: "INTEGER" },
            size: { type: "STRING", enum: ["S", "M", "L"] },
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
                propertyOrdering: ["name", "group", "alternatives", "portion", "flags"],
                required: ["name", "group", "alternatives", "portion", "flags"],
                properties: {
                  name: { type: "STRING" },
                  group,
                  alternatives: { type: "ARRAY", items: group, maxItems: 3 },
                  portion: { type: "STRING", enum: ["S", "M", "L"] },
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
