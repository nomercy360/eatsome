import {
  type MealRevision,
  mealRevisionSchema,
  preparationMethods,
  type RefinementRequest,
} from "../../src/contracts";
import { geminiCompositionSchema } from "./gemini";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import type { ModelCall } from "./types";

function userPrompt(input: RefinementRequest): string {
  const list = input.current
    .map((item, index) => `${index + 1}. ${item.label}, ${Math.round(item.grams)} g`)
    .join("\n");
  const dishes = input.dishes
    .map(
      (dish, index) =>
        `${index + 1}. ${dish.name}, count ${dish.count}, items ${dish.item_indices.join(", ") || "none"}`,
    )
    .join("\n");
  return `Current dishes:
${dishes || "(not supplied)"}

Current items:
${list || "(none)"}

The person says:
"""
${input.note}
"""

Return only what to add, revise, or remove. Keep everything else.`;
}

function geminiSchema(): Record<string, unknown> {
  const preparation = {
    type: "ARRAY",
    items: { type: "STRING", enum: [...preparationMethods] },
    maxItems: 4,
  };
  const grams = {
    type: "NUMBER",
    description: "Edible weight in grams — everything of this ingredient the person ate.",
  };
  // Required on every add and every revise. A row renamed without new figures
  // keeps the composition of the food it used to be, which is worse than an
  // uncorrected row because it looks corrected. Gemini emits exactly the
  // properties this schema names, so omitting it here would produce that row.
  const composition = geminiCompositionSchema();
  const label = {
    type: "STRING",
    description: "Short name for exactly ONE food. Never 'or', never 'and'.",
  };
  return {
    type: "OBJECT",
    propertyOrdering: ["add", "revise", "dish_counts", "dish_names", "remove", "notes"],
    required: ["add", "revise", "dish_counts", "dish_names", "remove", "notes"],
    properties: {
      add: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["label", "grams", "per_100g", "preparation", "alternatives"],
          required: ["label", "grams", "per_100g", "preparation", "alternatives"],
          properties: {
            label,
            grams,
            per_100g: composition,
            preparation,
            // Weighed as well as priced, and the same shape recognition
            // returns. A rival is rarely the size of the food first named, so
            // an alternative carrying only a name and a composition is one the
            // client can only apply at the old weight — a figure that looks
            // chosen and is not.
            alternatives: {
              type: "ARRAY",
              maxItems: 3,
              items: {
                type: "OBJECT",
                propertyOrdering: ["label", "grams", "per_100g"],
                required: ["label", "grams", "per_100g"],
                properties: { label, grams, per_100g: composition },
              },
            },
          },
        },
      },
      revise: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "label", "grams", "per_100g", "preparation"],
          required: ["index", "label", "grams", "per_100g", "preparation"],
          properties: {
            index: { type: "INTEGER" },
            label,
            grams,
            per_100g: composition,
            preparation,
          },
        },
      },
      dish_counts: {
        type: "ARRAY",
        description: "Dishes whose number of servings or discrete copies is wrong.",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "count"],
          required: ["index", "count"],
          properties: {
            index: { type: "INTEGER" },
            count: { type: "INTEGER" },
          },
        },
      },
      dish_names: {
        type: "ARRAY",
        description: "Dishes whose human-facing name is wrong.",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "name"],
          required: ["index", "name"],
          properties: {
            index: { type: "INTEGER" },
            name: { type: "STRING" },
          },
        },
      },
      remove: { type: "ARRAY", items: { type: "INTEGER" } },
      notes: { type: "STRING", nullable: true },
    },
  };
}

export function revisionSpec(input: RefinementRequest): ModelCall<MealRevision> {
  return {
    systemPrompt: MEAL_REVISION_SYSTEM_PROMPT,
    userPrompt: userPrompt(input),
    responseSchema: geminiSchema(),
    parse: (value) => mealRevisionSchema.parse(value),
  };
}
