import { mealRecognitionSchema, panelBases, preparationMethods } from "../../src/contracts";
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
  // Declared once and reused for the ingredient and each alternative. Gemini
  // emits exactly the properties a schema names and silently drops the rest,
  // which is how v16 shipped a weighing prompt that returned no weights — so
  // every field the prompt asks for has to appear here too.
  const composition = {
    type: "OBJECT",
    description:
      "Composition per 100 g of edible portion, as the food will be eaten. Never for the stated weight and never per serving.",
    propertyOrdering: ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
    required: ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
    properties: {
      protein: { type: "NUMBER", description: "Grams per 100 g." },
      fat: { type: "NUMBER", description: "Grams per 100 g." },
      carbohydrate: { type: "NUMBER", description: "Grams per 100 g." },
      kcal: { type: "NUMBER", description: "Kilocalories per 100 g." },
      sodium_mg: { type: "NUMBER", description: "Milligrams per 100 g." },
    },
  };
  return {
    type: "OBJECT",
    propertyOrdering: ["dishes"],
    required: ["dishes"],
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
                  "label",
                  "grams",
                  "per_100g",
                  "preparation",
                  "brand",
                  "sizes",
                  "alternatives",
                ],
                required: [
                  "label",
                  "grams",
                  "per_100g",
                  "preparation",
                  "brand",
                  "sizes",
                  "alternatives",
                ],
                properties: {
                  grams: {
                    type: "NUMBER",
                    description:
                      "Edible weight of this ingredient on the plate, in grams — everything of it that is there, already including every serving present. Never scale it by the dish's count; that is not applied afterwards either.",
                  },
                  label: {
                    type: "STRING",
                    description:
                      "Short human name for exactly ONE food. Never 'melon or pineapple', never 'ham and bacon' — two foods are two ingredients.",
                  },
                  per_100g: composition,
                  preparation: {
                    type: "ARRAY",
                    items: { type: "STRING", enum: [...preparationMethods] },
                    maxItems: 4,
                  },
                  brand: {
                    type: "STRING",
                    nullable: true,
                    description:
                      "The chain or manufacturer whose named menu item this row IS: 'Subway', 'McDonald's', 'Yoshinoya'. Null for anything cooked, served loose, or added on top of a menu item.",
                  },
                  sizes: {
                    type: "ARRAY",
                    description:
                      "Every size the chain sells this item in, each priced in full for that size. Empty when it comes one way only, and empty when there is no brand. A size is a different product, never a multiplier.",
                    maxItems: 6,
                    items: {
                      type: "OBJECT",
                      propertyOrdering: ["label", "grams", "per_100g", "basis"],
                      required: ["label", "grams", "per_100g", "basis"],
                      properties: {
                        label: {
                          type: "STRING",
                          description:
                            "The chain's own word for it, in the market's language: 'Footlong', 'L', '並盛', 'Grande'.",
                        },
                        grams: { type: "NUMBER", description: "Edible weight of that whole size." },
                        per_100g: composition,
                        basis: {
                          type: "STRING",
                          enum: ["published", "derived"],
                          description:
                            "`published` when the chain prints figures for this size; `derived` when they are arithmetic on another size, as a Subway Footlong is twice a Regular.",
                        },
                      },
                    },
                  },
                  alternatives: {
                    type: "ARRAY",
                    description:
                      "Other foods that could plausibly be right, most likely first, at most three. On a chain's menu item these are the neighbouring items on that menu. Empty when obvious.",
                    maxItems: 3,
                    items: {
                      type: "OBJECT",
                      propertyOrdering: ["label", "grams", "per_100g"],
                      required: ["label", "grams", "per_100g"],
                      properties: {
                        label: { type: "STRING" },
                        grams: {
                          type: "NUMBER",
                          description:
                            "What this food would weigh here — a rival menu item is not the same size as the one first named.",
                        },
                        per_100g: composition,
                      },
                    },
                  },
                },
              },
            },
          },
        },
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
      // Search, available rather than required. The model reaches for it on a
      // branded product and ignores it on food nobody published — measured, not
      // assumed: "two fried eggs, toast and a black coffee" comes back with no
      // thinking tokens and the same three dishes it always had, while a Subway
      // footlong spends 517 and lands on the printed figure.
      //
      // It is worth a lot on exactly the food the app was worst at. A Subway JP
      // American Clubhouse footlong publishes 698 kcal; ungrounded this prompt
      // answered 845 and 865 on two runs, grounded it answered 700 and 697.
      // Composition the model recites from a food table is already 0–3%; a
      // chain's own recipe is not in any food table, and that is the gap.
      //
      // What it does *not* buy is provenance. `generateContent` returns no
      // grounding metadata alongside a response schema, so there is no URL to
      // keep and nothing here may be stamped `published` — a grounded answer is
      // a better estimate, and the app says "estimated" about it. The citation
      // path is `ai/published.ts`, which reads one named page and can prove it.
      ...(env.RECOGNITION_SEARCH === "on" ? { tools: [{ googleSearch: {} }] } : {}),
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
