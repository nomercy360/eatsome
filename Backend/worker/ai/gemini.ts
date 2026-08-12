import {
  compositionHints,
  foodKinds,
  mealRecognitionSchema,
  panelBases,
  preparationMethods,
} from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

/**
 * The same contract as the OpenAI path, in Gemini's OpenAPI subset.
 *
 * It has to be written out rather than derived from the zod schema like the
 * OpenAI one: Gemini rejects `additionalProperties`, spells a nullable field as
 * a flag rather than a union type, and wants `propertyOrdering` to keep the
 * emitted keys stable. The enums come from the same constants, so a new food
 * kind or facet still reaches both providers from one edit.
 */
export function geminiResponseSchema(): Record<string, unknown> {
  const kind = { type: "STRING", enum: [...foodKinds] };
  return {
    type: "OBJECT",
    propertyOrdering: ["dishes", "other_meals_visible", "notes"],
    required: ["dishes", "other_meals_visible", "notes"],
    properties: {
      dishes: {
        type: "ARRAY",
        description:
          "One entry per named thing on the closest place setting. Fried chicken, rice and miso soup are three dishes.",
        items: {
          type: "OBJECT",
          propertyOrdering: ["name", "count", "panel", "ingredients"],
          required: ["name", "count", "panel", "ingredients"],
          properties: {
            name: {
              type: "STRING",
              description:
                "What you would call it out loud: 'som tam', 'fried rice', 'beer'. A name, never a list of contents.",
            },
            count: {
              type: "INTEGER",
              description:
                "How many servings of this dish are present. Two plates of fried rice is one dish with count 2. A label on the weights below, never a multiplier of them.",
            },
            panel: {
              type: "OBJECT",
              nullable: true,
              description:
                "Nutrition figures PRINTED on packaging, a price card or a menu, for one serving as the label defines it. Transcribe only — never estimate from the look of the food. Null when nothing is printed, or when it cannot be read.",
              propertyOrdering: [
                "protein",
                "calories",
                "fat",
                "carbohydrate",
                "salt",
                "sodium",
                "caffeine",
                "basis",
                "net_ml",
                "net_g",
              ],
              required: [
                "protein",
                "calories",
                "fat",
                "carbohydrate",
                "salt",
                "sodium",
                "caffeine",
                "basis",
                "net_ml",
                "net_g",
              ],
              properties: {
                protein: { type: "NUMBER", nullable: true, description: "Grams." },
                calories: { type: "NUMBER", nullable: true, description: "kcal." },
                fat: { type: "NUMBER", nullable: true, description: "Grams." },
                carbohydrate: { type: "NUMBER", nullable: true, description: "Grams." },
                salt: {
                  type: "NUMBER",
                  nullable: true,
                  description: "Grams of salt equivalent — 食塩相当量. Never converted to sodium.",
                },
                sodium: {
                  type: "NUMBER",
                  nullable: true,
                  description: "Grams, only if printed as sodium.",
                },
                caffeine: { type: "NUMBER", nullable: true, description: "Milligrams." },
                basis: {
                  type: "STRING",
                  enum: [...panelBases],
                  nullable: true,
                  description:
                    "What the figures are counted against, copied from the heading above them. Japanese drink labels usually print per 100ml.",
                },
                net_ml: {
                  type: "NUMBER",
                  nullable: true,
                  description: "Contents in millilitres as printed, e.g. 355 for 内容量 355ml.",
                },
                net_g: { type: "NUMBER", nullable: true, description: "Contents in grams." },
              },
            },
            ingredients: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                // `grams` is declared here and not merely described in the
                // prompt because Gemini emits exactly the properties this
                // schema names and silently drops the rest. It was missing for
                // the whole of v16: the prompt asked for a weight on every
                // ingredient, the eval schema had somewhere to put one and
                // graded it well, and every answer the app actually received
                // came back weightless and used the ladder grams replaced.
                propertyOrdering: [
                  "kind",
                  "grams",
                  "label",
                  "preparation",
                  "composition_hints",
                  "alternatives",
                ],
                required: [
                  "kind",
                  "grams",
                  "label",
                  "preparation",
                  "composition_hints",
                  "alternatives",
                ],
                properties: {
                  kind: { ...kind, description: "The ingredient's broad nutrition-oriented kind." },
                  grams: {
                    type: "NUMBER",
                    description:
                      "Edible weight of this ingredient on the plate, in grams — everything of it that is there, already including every serving present. Never scale it by the dish's count; that is not applied afterwards either.",
                  },
                  label: {
                    type: "STRING",
                    description:
                      "Short human name for one food. Never a hedge like 'melon or pineapple'.",
                  },
                  preparation: {
                    type: "ARRAY",
                    items: { type: "STRING", enum: [...preparationMethods] },
                    maxItems: 4,
                  },
                  composition_hints: {
                    type: "ARRAY",
                    items: { type: "STRING", enum: [...compositionHints] },
                    maxItems: 5,
                  },
                  alternatives: {
                    type: "ARRAY",
                    description:
                      "Other foods that could plausibly be right, most likely first, at most three. Empty when obvious.",
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
          },
        },
      },
      other_meals_visible: {
        type: "BOOLEAN",
        description: "True when food on another tray or place setting was deliberately ignored.",
      },
      notes: {
        type: "STRING",
        nullable: true,
        description: "Ambiguities worth a human glance. Null if none.",
      },
    },
  };
}

type GeminiResponse = {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string; thought?: boolean }> };
    finishReason?: string;
  }>;
  promptFeedback?: { blockReason?: string };
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
  error?: { message?: string };
};

export async function requestGeminiRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const model = env.GEMINI_RECOGNITION_MODEL;
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: {
      // In a header, never the query string: URLs end up in logs.
      "x-goog-api-key": env.GEMINI_API_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: spec.systemPrompt }] },
      contents: [
        {
          role: "user",
          parts: hasImage(input)
            ? [
                { text: spec.userPrompt },
                { inlineData: { mimeType: input.mimeType, data: input.imageBase64 } },
              ]
            : [{ text: spec.userPrompt }],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: spec.geminiSchema ?? geminiResponseSchema(),
        thinkingConfig: { thinkingLevel: env.GEMINI_THINKING_LEVEL || "low" },
        // Gemini's counterpart to OpenAI's image detail: it decides how many
        // tokens a picture is worth reading at. Omitted when unset so the API
        // default stands — an invalid enum here fails the whole request, so it
        // is opt-in and belongs in the eval before it belongs in production.
        ...(env.GEMINI_MEDIA_RESOLUTION ? { mediaResolution: env.GEMINI_MEDIA_RESOLUTION } : {}),
      },
    }),
  });

  const body = (await response.json()) as GeminiResponse;
  if (!response.ok) {
    throw new HttpError(
      502,
      `Gemini returned ${response.status}: ${body.error?.message ?? "no body"}`,
    );
  }
  if (body.promptFeedback?.blockReason) {
    throw new HttpError(422, `Gemini declined the photo: ${body.promptFeedback.blockReason}`);
  }

  const candidate = body.candidates?.[0];
  if (!candidate) throw new HttpError(502, "Gemini returned no meal recognition output.");
  // Anything but STOP means a partial answer, and a truncated meal that still
  // parses silently drops food.
  if (candidate.finishReason && candidate.finishReason !== "STOP") {
    throw new HttpError(502, `Gemini stopped early (${candidate.finishReason}).`);
  }

  const rawModelJson = (candidate.content?.parts ?? [])
    .filter((part) => part.thought !== true)
    .map((part) => part.text ?? "")
    .join("");
  if (!rawModelJson) throw new HttpError(502, "Gemini returned no meal recognition output.");

  return {
    // Parsed against the production contract only when that is what was asked
    // for; a candidate schema is validated by the caller that supplied it.
    recognition: spec.geminiSchema
      ? (JSON.parse(rawModelJson) as never)
      : mealRecognitionSchema.parse(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.headers.get("x-request-id"),
    inputTokens: body.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: body.usageMetadata?.candidatesTokenCount ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
