import type { RecognitionRequest } from "../../src/contracts";
import { foodGroups, mealRecognitionSchema, portions } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { MEAL_RECOGNITION_SYSTEM_PROMPT, MEAL_RECOGNITION_USER_PROMPT } from "./prompt";
import type { ProviderRecognition } from "./types";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

/**
 * The same contract as the OpenAI path, in Gemini's OpenAPI subset.
 *
 * It has to be written out rather than derived from the zod schema like the
 * OpenAI one: Gemini rejects `additionalProperties`, spells a nullable field as
 * a flag rather than a union type, and wants `propertyOrdering` to keep the
 * emitted keys stable. The enums come from the same constants, so a new food
 * group still reaches both providers from one edit.
 */
export function geminiResponseSchema(): Record<string, unknown> {
  const group = { type: "STRING", enum: [...foodGroups] };
  return {
    type: "OBJECT",
    propertyOrdering: ["items", "other_meals_visible", "notes"],
    required: ["items", "other_meals_visible", "notes"],
    properties: {
      items: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          propertyOrdering: ["group", "portion", "label", "alternatives"],
          required: ["group", "portion", "label", "alternatives"],
          properties: {
            group: { ...group, description: "Your single best answer for this item." },
            portion: { type: "STRING", enum: [...portions] },
            label: {
              type: "STRING",
              nullable: true,
              description:
                "Short human name for one food. Never a hedge like 'melon or pineapple'.",
            },
            alternatives: {
              type: "ARRAY",
              description:
                "Other groups that could plausibly be right for this item, most likely first, at most three. Empty when the group is obvious.",
              items: group,
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
  input: RecognitionRequest,
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
      systemInstruction: { parts: [{ text: MEAL_RECOGNITION_SYSTEM_PROMPT }] },
      contents: [
        {
          role: "user",
          parts: [
            { text: MEAL_RECOGNITION_USER_PROMPT },
            { inlineData: { mimeType: input.mimeType, data: input.imageBase64 } },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: geminiResponseSchema(),
        thinkingConfig: { thinkingLevel: "low" },
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
    recognition: mealRecognitionSchema.parse(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.headers.get("x-request-id"),
    inputTokens: body.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: body.usageMetadata?.candidatesTokenCount ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
