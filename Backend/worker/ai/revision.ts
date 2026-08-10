import { foodGroups, mealRevisionJsonSchema, type RefinementRequest } from "../../src/contracts";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import type { RecognitionSpec } from "./spec";

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
    systemPrompt: MEAL_REVISION_SYSTEM_PROMPT,
    userPrompt: userPrompt(input),
    jsonSchema: mealRevisionJsonSchema(),
    geminiSchema: geminiSchema(),
    schemaName: "meal_revision",
  };
}
