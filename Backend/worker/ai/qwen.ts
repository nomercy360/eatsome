import OpenAI from "openai";

import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

/**
 * Qwen through an OpenAI-compatible endpoint — DashScope by default, or
 * QwenCloud or OpenRouter by pointing `QWEN_BASE_URL` elsewhere.
 *
 * It reuses the OpenAI SDK but not the OpenAI path, and the difference is worth
 * naming when reading eval results: `LunaSession` and the proxy's OpenAI client
 * use the Responses API with `text.format: json_schema`, which compatibility
 * mode does not implement. This goes through chat completions with
 * `response_format`, which the compatible providers do implement. Same prompt,
 * same schema, slightly different transport — so a gap between Qwen and the
 * others is a gap in the model plus a gap in how the answer was constrained,
 * not the model alone.
 */
export async function requestQwenRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({
    apiKey: env.QWEN_API_KEY,
    baseURL: env.QWEN_BASE_URL || "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  });

  const response = await client.chat.completions.create({
    model: env.QWEN_RECOGNITION_MODEL,
    // DashScope takes this outside the OpenAI surface; harmless where ignored.
    ...(env.QWEN_ENABLE_THINKING ? { enable_thinking: env.QWEN_ENABLE_THINKING === "true" } : {}),
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
  if (choice?.finish_reason && !["stop", "length"].includes(choice.finish_reason)) {
    throw new HttpError(502, `Qwen stopped early (${choice.finish_reason}).`);
  }
  if (choice?.finish_reason === "length") {
    throw new HttpError(502, "Qwen stopped early (max tokens); the meal would be partial.");
  }

  const rawModelJson = choice?.message?.content ?? "";
  if (!rawModelJson) throw new HttpError(502, "Qwen returned no meal recognition output.");

  return {
    recognition: parseFor(spec)(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.id ?? null,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
