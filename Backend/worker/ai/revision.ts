import {
  mealRevisionJsonSchema,
  preparationMethods,
  type RefinementRequest,
} from "../../src/contracts";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import type { RecognitionSpec } from "./spec";

function userPrompt(input: RefinementRequest): string {
  const list = input.current
    .map((item, index) => `${index + 1}. ${item.label}, ${Math.round(item.grams)} g`)
    .join("\n");
  return `Current items:
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
  const composition = {
    type: "OBJECT",
    description: "Composition per 100 g of the food as it now stands, as prepared and as eaten.",
    propertyOrdering: ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
    required: ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
    properties: {
      protein: { type: "NUMBER" },
      fat: { type: "NUMBER" },
      carbohydrate: { type: "NUMBER" },
      kcal: { type: "NUMBER" },
      sodium_mg: { type: "NUMBER" },
    },
  };
  const label = {
    type: "STRING",
    description: "Short name for exactly ONE food. Never 'or', never 'and'.",
  };
  return {
    type: "OBJECT",
    propertyOrdering: ["add", "revise", "remove", "notes"],
    required: ["add", "revise", "remove", "notes"],
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
            alternatives: {
              type: "ARRAY",
              maxItems: 3,
              items: {
                type: "OBJECT",
                propertyOrdering: ["label", "per_100g"],
                required: ["label", "per_100g"],
                properties: { label: { type: "STRING" }, per_100g: composition },
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
      remove: { type: "ARRAY", items: { type: "INTEGER" } },
      notes: { type: "STRING", nullable: true },
    },
  };
}

export function revisionSpec(input: RefinementRequest): RecognitionSpec {
  return {
    systemPrompt: MEAL_REVISION_SYSTEM_PROMPT,
    userPrompt: userPrompt(input),
    jsonSchema: mealRevisionJsonSchema(),
    geminiSchema: geminiSchema(),
    schemaName: "meal_revision",
  };
}
