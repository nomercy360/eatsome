import OpenAI from "openai";
import type { Env } from "../env";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

export async function requestOpenAIRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({ apiKey: env.OPENAI_API_KEY });
  const content: OpenAI.Responses.ResponseInputMessageContentList = [
    { type: "input_text", text: spec.userPrompt },
  ];
  if (hasImage(input)) {
    content.push({
      type: "input_image",
      image_url: `data:${input.mimeType};base64,${input.imageBase64}`,
      // `low` bills a flat 85 image tokens whatever you send, which is the same
      // thing as saying it looks at roughly 512px and no more — enough for
      // "rice and fish", not enough to read the print on a carton. Sending a
      // bigger photo while this says `low` changes nothing but the upload.
      detail: (env.OPENAI_IMAGE_DETAIL || "high") as "high",
    });
  }
  const response = await client.responses.create({
    model: env.OPENAI_RECOGNITION_MODEL,
    instructions: spec.systemPrompt,
    input: [{ role: "user", content }],
    reasoning: { effort: (env.OPENAI_REASONING_EFFORT || "low") as "low" },
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: spec.schemaName,
        schema: spec.jsonSchema,
        strict: true,
      },
    },
    store: false,
  });

  if (!response.output_text) throw new Error("OpenAI returned no meal recognition output.");
  const recognition = parseFor(spec)(JSON.parse(response.output_text) as unknown);
  return {
    recognition,
    rawModelJson: response.output_text,
    requestId: response.id ?? null,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
