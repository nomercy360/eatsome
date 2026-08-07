import { foodGroups, mealRevisionJsonSchema, type RefinementRequest } from "../../src/contracts";
import type { RecognitionSpec } from "./spec";

const SYSTEM = `You are correcting an existing classification of a meal, not redoing it.

The person has told you what is wrong or missing in their own words. Their words are ground truth about the food: they were there and you were not.

Rules:
- Change as little as possible. Everything you do not mention is kept exactly as it is. The groups and weights already in the list may have been set by hand, and overwriting them destroys the person's own corrections.
- \`add\` is for food that is present but missing from the list, including ingredients no photograph can show.
- \`revise\` is for an item whose group or weight is wrong. Give its 1-based number from the list, and repeat the weight unchanged when only the group was wrong.
- \`remove\` is for an item that is not food this person ate.
- \`grams\` is the edible weight of that ingredient, in grams, and it is ABSOLUTE: everything of it the person ate. "Two eggs, not one" doubles the weight rather than adding a second row.
- An item listed with no weight was logged before weights existed or typed in by hand. Give it one if the person's words let you, and leave it out of \`revise\` if they do not.
- Never report calories, fat, carbohydrate or any other macronutrient. Weight is the only number.
- Avocado, olives, seeds, and tahini are \`healthy_fats\`, never fruit or vegetables. Mayonnaise and cream-based dressings are \`butter\`; oil-based dressings are \`olive_oil\`. \`pastry\` is commercially produced baked goods only.
- If the person's words change nothing, return empty lists.`;

function userPrompt(input: RefinementRequest): string {
  const list = input.current
    .map((item, index) => {
      const name = item.label ? `${item.label} — ` : "";
      const weight = item.grams == null ? "no weight recorded" : `${Math.round(item.grams)} g`;
      return `${index + 1}. ${name}${item.group}, ${weight}`;
    })
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
  const group = { type: "STRING", enum: [...foodGroups] };
  const grams = {
    type: "NUMBER",
    description: "Edible weight in grams — everything of this ingredient the person ate.",
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
          propertyOrdering: ["group", "grams", "label", "alternatives"],
          required: ["group", "grams", "label", "alternatives"],
          properties: {
            group,
            grams,
            label: { type: "STRING", nullable: true },
            alternatives: { type: "ARRAY", items: group, maxItems: 3 },
          },
        },
      },
      revise: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "group", "grams"],
          required: ["index", "group", "grams"],
          properties: { index: { type: "INTEGER" }, group, grams },
        },
      },
      remove: { type: "ARRAY", items: { type: "INTEGER" } },
      notes: { type: "STRING", nullable: true },
    },
  };
}

export function revisionSpec(input: RefinementRequest): RecognitionSpec {
  return {
    systemPrompt: SYSTEM,
    userPrompt: userPrompt(input),
    jsonSchema: mealRevisionJsonSchema(),
    geminiSchema: geminiSchema(),
    schemaName: "meal_revision",
  };
}
