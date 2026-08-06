import OpenAI from "openai";

import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

/**
 * OpenRouter, for models no first-party client here reaches — Grok and Muse.
 *
 * It is a separate provider rather than a repointed `QWEN_BASE_URL`, even
 * though qwen.ts documents that trick. Sharing one row would mean a single
 * `QWEN_RECOGNITION_MODEL` for two vendors and one key variable for two
 * accounts, so the matrix could not hold Qwen on DashScope and Grok on
 * OpenRouter at the same time — which is exactly the arrangement wanted.
 *
 * Same transport as qwen.ts: chat completions with `response_format`, not the
 * Responses API. Worth remembering when reading a gap between these rows and
 * the OpenAI ones — it is a gap in the model plus a gap in how the answer was
 * constrained. OpenRouter forwards `json_schema` only to models that implement
 * it and errors otherwise, so a provider failure here is a capability fact
 * about the model, not a bug in this file.
 */
export async function requestOpenRouterRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({
    apiKey: env.OPENROUTER_API_KEY,
    baseURL: env.OPENROUTER_BASE_URL || "https://openrouter.ai/api/v1",
  });

  const response = await client.chat.completions.create({
    model: env.OPENROUTER_RECOGNITION_MODEL,
    messages: [
      { role: "system", content: spec.systemPrompt },
      {
        role: "user",
        content: [
          { type: "text", text: spec.userPrompt },
          ...(hasImage(input)
            ? [
                {
                  type: "image_url" as const,
                  image_url: { url: `data:${input.mimeType};base64,${input.imageBase64}` },
                },
              ]
            : []),
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: spec.schemaName,
        strict: true,
        schema: spec.jsonSchema,
      },
    },
  });

  const choice = response.choices[0];
  if (choice?.finish_reason === "length") {
    throw new HttpError(502, "OpenRouter stopped early (max tokens); the meal would be partial.");
  }
  if (choice?.finish_reason && !["stop", "length"].includes(choice.finish_reason)) {
    throw new HttpError(502, `OpenRouter stopped early (${choice.finish_reason}).`);
  }

  const rawModelJson = choice?.message?.content ?? "";
  if (!rawModelJson) throw new HttpError(502, "OpenRouter returned no meal recognition output.");

  return {
    recognition: parseFor(spec)(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.id ?? null,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
