import { forkEvidence, panelBases, preparationMethods } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { hasImage, type ModelAnswer, type ModelCall, type ProviderInput } from "./types";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

/**
 * The composition block, in Gemini's dialect, once — used by every ingredient,
 * alternative and fork option here and by the revision schema in `revision.ts`, so an
 * eighth figure added to the Zod contract has exactly one other place to be
 * added and the drift test in `gemini.test.ts` says when it was not.
 */
export function geminiCompositionSchema(): Record<string, unknown> {
  return {
    type: "OBJECT",
    description:
      "Composition per 100 g of edible portion, as the food will be eaten. Never for the stated weight and never per serving. All seven figures, always: zero is a statement about the food, not an omission.",
    propertyOrdering: [
      "protein",
      "fat",
      "carbohydrate",
      "kcal",
      "sodium_mg",
      "alcohol",
      "caffeine_mg",
    ],
    required: ["protein", "fat", "carbohydrate", "kcal", "sodium_mg", "alcohol", "caffeine_mg"],
    properties: {
      protein: { type: "NUMBER", description: "Grams per 100 g." },
      fat: { type: "NUMBER", description: "Grams per 100 g." },
      carbohydrate: { type: "NUMBER", description: "Grams per 100 g." },
      kcal: {
        type: "NUMBER",
        description: "Kilocalories per 100 g, including the energy of any alcohol.",
      },
      sodium_mg: { type: "NUMBER", description: "Milligrams per 100 g." },
      alcohol: {
        type: "NUMBER",
        description:
          "Grams of ethanol per 100 g. Zero for anything that is not an alcoholic drink or cooked with alcohol that remains.",
      },
      caffeine_mg: {
        type: "NUMBER",
        description:
          "Milligrams of caffeine per 100 g, from the specific drink and preparation — drip coffee, espresso, decaf, black tea and matcha are not interchangeable. Zero for food that has none.",
      },
    },
  };
}

/**
 * The Zod contract, restated in Gemini's OpenAPI subset.
 *
 * It has to be written out rather than derived: Gemini rejects
 * `additionalProperties`, spells a nullable field as a flag rather than a union
 * type, and wants `propertyOrdering` to keep the emitted keys stable. It is
 * therefore the one schema in the app that can quietly fall behind the
 * contract — and it did once, for `grams`, for a month. `gemini.test.ts`
 * compares it field by field against `mealRecognitionJsonSchema()`, which is
 * the only reason that comparison schema still exists now that no provider is
 * handed it.
 */
export function geminiResponseSchema(): Record<string, unknown> {
  const composition = geminiCompositionSchema();
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
                "Nutrition figures printed on packaging, a price card or a menu, transcribed. Never an estimate — caffeine and alcohol that are not printed belong in per_100g. Null for every unlabelled food.",
              propertyOrdering: [
                "protein",
                "calories",
                "fat",
                "carbohydrate",
                "salt",
                "sodium",
                "alcohol",
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
                "alcohol",
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
                alcohol: {
                  type: "NUMBER",
                  nullable: true,
                  description: "Grams of alcohol, only if printed as grams. ABV is not this field.",
                },
                caffeine: {
                  type: "NUMBER",
                  nullable: true,
                  description: "Milligrams, only if printed.",
                },
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
                  "forks",
                  "alternatives",
                ],
                required: [
                  "label",
                  "grams",
                  "per_100g",
                  "preparation",
                  "brand",
                  "forks",
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
                  forks: {
                    type: "ARRAY",
                    description:
                      "Choices the input leaves open that move this row's figures materially — size, milk, which drink, dressing, sugar. Each is a set of complete priced answers for the SAME food, one of them being what the row already assumes. Empty is the normal case: nothing on home cooking or a canteen tray, nothing on food that comes one way, nothing whose options differ by little. At most three, most consequential first.",
                    maxItems: 3,
                    items: {
                      type: "OBJECT",
                      propertyOrdering: ["axis", "chosen_from", "options"],
                      required: ["axis", "chosen_from", "options"],
                      properties: {
                        axis: {
                          type: "STRING",
                          description:
                            "One or two lowercase words naming the choice: 'size', 'milk', 'drink', 'dressing', 'sugar'.",
                        },
                        chosen_from: {
                          type: "STRING",
                          enum: [...forkEvidence],
                          description:
                            "How the chosen option was decided: `stated` when the person's words name it, `seen` when the photograph shows it (a size printed on the cup, a 6-inch wrapper), `assumed` when nothing in the input decides it and you picked the usual one.",
                        },
                        // No min/maxItems on this array: Gemini rejects the
                        // request when both it and the enclosing `forks`
                        // array carry maxItems, and accepts either alone.
                        // Two to six is stated in the prompt and enforced by
                        // the Zod contract.
                        options: {
                          type: "ARRAY",
                          items: {
                            type: "OBJECT",
                            propertyOrdering: ["label", "grams", "per_100g", "basis", "chosen"],
                            required: ["label", "grams", "per_100g", "basis", "chosen"],
                            properties: {
                              label: {
                                type: "STRING",
                                description:
                                  "The option in the words the person would use, in the market's own language: 'Footlong', 'L', '並盛', 'Grande', 'oat milk', 'Coke Zero'. One option per label.",
                              },
                              grams: {
                                type: "NUMBER",
                                description:
                                  "Edible weight of the whole row if this option is right.",
                              },
                              per_100g: composition,
                              basis: {
                                type: "STRING",
                                enum: ["published", "derived"],
                                description:
                                  "`published` when someone prints figures for exactly this option; `derived` when they are arithmetic on another one, as a Subway Footlong is twice a Regular.",
                              },
                              chosen: {
                                type: "BOOLEAN",
                                description:
                                  "True on exactly one option per fork: the one the row's own grams and per_100g already assume.",
                              },
                            },
                          },
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

/**
 * Ask Gemini one question and read its answer.
 *
 * Generic over the call, so recognition and correction share the transport and
 * nothing else: each brings its own prompt, its own response schema and its own
 * parser, and this function never learns which it is serving.
 */
export async function askGemini<T>(
  env: Env,
  input: ProviderInput,
  call: ModelCall<T>,
): Promise<ModelAnswer<T>> {
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
      systemInstruction: { parts: [{ text: call.systemPrompt }] },
      contents: [
        {
          role: "user",
          parts: hasImage(input)
            ? [
                { text: call.userPrompt },
                { inlineData: { mimeType: input.mimeType, data: input.imageBase64 } },
              ]
            : [{ text: call.userPrompt }],
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
      // keep and no figure here may be called anything but `model` — a grounded
      // answer is a better estimate, and the app says "estimated" about it.
      // There is no citation path any more: the one that fetched a brand's own
      // page resolved one chain in seven and was deleted in favour of this.
      ...(env.RECOGNITION_SEARCH === "on" ? { tools: [{ googleSearch: {} }] } : {}),
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: call.responseSchema,
        thinkingConfig: { thinkingLevel: env.GEMINI_THINKING_LEVEL || "low" },
        // How many tokens a picture is worth reading at, which is what decides
        // whether small print on packaging survives. Omitted when unset so the
        // API default stands — an invalid enum here fails the whole request, so
        // it is opt-in and belongs in the eval before it belongs in production.
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
    value: call.parse(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.headers.get("x-request-id"),
    inputTokens: body.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: body.usageMetadata?.candidatesTokenCount ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
