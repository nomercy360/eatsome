import OpenAI from "openai";

import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

/**
 * Muse Spark on the Meta Model API.
 *
 * This reuses the OpenAI SDK *and* the OpenAI path — the Responses API with
 * `text.format: json_schema` — because Meta implements that surface natively
 * rather than through a compatibility shim. That is the difference worth naming
 * against `qwen.ts`, which shares the SDK but drops to chat completions with
 * `response_format`: a Qwen gap is a model gap plus a transport gap, and a Muse
 * Spark gap is the model, held to the same constraint Luna is held to.
 *
 * It is its own file rather than a `baseURL` on `openai.ts` because the two
 * disagree on more than a host: Meta prices and bills its own way, and the eval
 * matrix keys cost on the model row. Sharing the function would make one
 * vendor's key the other's default the first time either grew an option.
 *
 * `muse-spark-1.2-contributor` is deliberately not the default and should not
 * be made one: it is a fifth of the price because Meta may train on prompts and
 * completions sent to it, and the prompts here are photographs of what someone
 * ate.
 */
export async function requestMetaRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({
    apiKey: env.META_API_KEY,
    baseURL: env.META_BASE_URL || "https://api.meta.ai/v1",
  });

  const content: OpenAI.Responses.ResponseInputMessageContentList = [
    { type: "input_text", text: spec.userPrompt },
  ];
  if (hasImage(input)) {
    content.push({
      type: "input_image",
      image_url: `data:${input.mimeType};base64,${input.imageBase64}`,
      // Same argument as `openai.ts`: `low` is a flat, small image budget, which
      // is enough for "rice and fish" and not enough to read a nutrition panel.
      detail: (env.META_IMAGE_DETAIL || "high") as "high",
    });
  }

  const response = await client.responses.create({
    model: env.META_RECOGNITION_MODEL,
    instructions: spec.systemPrompt,
    input: [{ role: "user", content }],
    // Muse Spark is a reasoning model and spends freely when uncapped — 2196 of
    // 3043 output tokens on the first probe, against 1141 with this set. `low`
    // is also what keeps it comparable with Luna's effort and Gemini's
    // `thinkingLevel`, which is the only reason the matrix means anything.
    reasoning: { effort: (env.META_REASONING_EFFORT || "low") as "low" },
    text: {
      format: {
        type: "json_schema",
        name: spec.schemaName,
        schema: spec.jsonSchema,
        strict: true,
      },
    },
    store: false,
  });

  const rawModelJson = response.output_text;
  if (!rawModelJson) {
    throw new HttpError(502, "Muse Spark returned no meal recognition output.");
  }

  return {
    recognition: parseFor(spec)(JSON.parse(rawModelJson) as unknown),
    rawModelJson,
    requestId: response.id ?? null,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
