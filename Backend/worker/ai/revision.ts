import {
  foodGroups,
  mealRevisionJsonSchema,
  portions,
  type RefinementRequest,
} from "../../src/contracts";
import type { RecognitionSpec } from "./spec";

const SYSTEM = `You are correcting an existing classification of a meal, not redoing it.

The person has told you what is wrong or missing in their own words. Their words are ground truth about the food: they were there and you were not.

Rules:
- Change as little as possible. Everything you do not mention is kept exactly as it is. The groups and portions already in the list may have been set by hand, and overwriting them destroys the person's own corrections.
- \`add\` is for food that is present but missing from the list, including ingredients no photograph can show.
- \`revise\` is for an item whose group or portion is wrong. Give its 1-based number from the list.
- \`remove\` is for an item that is not food this person ate.
- Report groups and coarse portions only. Never calories, grams, or macronutrients.
- Portion is relative to a normal serving for one adult: small is about half, medium is one, large is two or more.
- Avocado, olives, seeds, and tahini are \`healthy_fats\`, never fruit or vegetables. Mayonnaise and cream-based dressings are \`butter\`; oil-based dressings are \`olive_oil\`. \`pastry\` is commercially produced baked goods only.
- If the person's words change nothing, return empty lists.`;

function userPrompt(input: RefinementRequest): string {
  const list = input.current
    .map((item, index) => {
      const name = item.label ? `${item.label} — ` : "";
      return `${index + 1}. ${name}${item.group}, ${item.portion}`;
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
  const portion = { type: "STRING", enum: [...portions] };
  return {
    type: "OBJECT",
    propertyOrdering: ["add", "revise", "remove", "notes"],
    required: ["add", "revise", "remove", "notes"],
    properties: {
      add: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["group", "portion", "label", "alternatives"],
          required: ["group", "portion", "label", "alternatives"],
          properties: {
            group,
            portion,
            label: { type: "STRING", nullable: true },
            alternatives: { type: "ARRAY", items: group, maxItems: 3 },
          },
        },
      },
      revise: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "group", "portion"],
          required: ["index", "group", "portion"],
          properties: { index: { type: "INTEGER" }, group, portion },
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
