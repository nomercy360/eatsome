import {
  compositionHints,
  foodKinds,
  mealRevisionJsonSchema,
  preparationMethods,
  type RefinementRequest,
} from "../../src/contracts";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import type { RecognitionSpec } from "./spec";

function userPrompt(input: RefinementRequest): string {
  const list = input.current
    .map((item, index) => {
      const name = item.label ? `${item.label} — ` : "";
      const weight = item.grams == null ? "no weight recorded" : `${Math.round(item.grams)} g`;
      return `${index + 1}. ${name}${item.kind}, ${weight}`;
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
  const kind = { type: "STRING", enum: [...foodKinds] };
  const preparation = {
    type: "ARRAY",
    items: { type: "STRING", enum: [...preparationMethods] },
    maxItems: 4,
  };
  const hints = {
    type: "ARRAY",
    items: { type: "STRING", enum: [...compositionHints] },
    maxItems: 5,
  };
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
          propertyOrdering: [
            "kind",
            "grams",
            "label",
            "preparation",
            "composition_hints",
            "alternatives",
          ],
          required: ["kind", "grams", "label", "preparation", "composition_hints", "alternatives"],
          properties: {
            kind,
            grams,
            label: { type: "STRING" },
            preparation,
            composition_hints: hints,
            alternatives: {
              type: "ARRAY",
              maxItems: 3,
              items: {
                type: "OBJECT",
                propertyOrdering: ["label", "kind"],
                required: ["label", "kind"],
                properties: { label: { type: "STRING" }, kind },
              },
            },
          },
        },
      },
      revise: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["index", "kind", "grams", "preparation", "composition_hints"],
          required: ["index", "kind", "grams", "preparation", "composition_hints"],
          properties: {
            index: { type: "INTEGER" },
            kind,
            grams,
            preparation,
            composition_hints: hints,
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
