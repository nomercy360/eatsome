import OpenAI from "openai";
import type { RecognitionRequest } from "../../src/contracts";
import { mealRecognitionJsonSchema, mealRecognitionSchema } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { MEAL_RECOGNITION_SYSTEM_PROMPT, MEAL_RECOGNITION_USER_PROMPT } from "./prompt";
import type { ProviderRecognition } from "./types";

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
  input: RecognitionRequest,
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({
    apiKey: env.QWEN_API_KEY,
    baseURL: env.QWEN_BASE_URL || "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  });

  const response = await client.chat.completions.create({
    model: env.QWEN_RECOGNITION_MODEL,
    messages: [
      { role: "system", content: MEAL_RECOGNITION_SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          { type: "text", text: MEAL_RECOGNITION_USER_PROMPT },
          {
            type: "image_url",
            image_url: { url: `data:${input.mimeType};base64,${input.imageBase64}` },
          },
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "meal_recognition",
        strict: true,
        schema: mealRecognitionJsonSchema(),
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
    recognition: mealRecognitionSchema.parse(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.id ?? null,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
