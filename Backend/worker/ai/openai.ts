import OpenAI from "openai";
import type { RecognitionRequest } from "../../src/contracts";
import type { Env } from "../env";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import type { ProviderRecognition } from "./types";

export async function requestOpenAIRecognition(
  env: Env,
  input: RecognitionRequest,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({ apiKey: env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: env.OPENAI_RECOGNITION_MODEL,
    instructions: spec.systemPrompt,
    input: [
      {
        role: "user",
        content: [
          { type: "input_text", text: spec.userPrompt },
          {
            type: "input_image",
            image_url: `data:${input.mimeType};base64,${input.imageBase64}`,
            detail: "low",
          },
        ],
      },
    ],
    reasoning: { effort: "low" },
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
