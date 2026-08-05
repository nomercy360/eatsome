import OpenAI from "openai";
import {
  mealRecognitionJsonSchema,
  mealRecognitionSchema,
  type RecognitionRequest,
} from "../../src/contracts";
import type { Env } from "../env";
import { MEAL_RECOGNITION_SYSTEM_PROMPT, MEAL_RECOGNITION_USER_PROMPT } from "./prompt";
import type { ProviderRecognition } from "./types";

export async function requestOpenAIRecognition(
  env: Env,
  input: RecognitionRequest,
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const client = new OpenAI({ apiKey: env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: env.OPENAI_RECOGNITION_MODEL,
    instructions: MEAL_RECOGNITION_SYSTEM_PROMPT,
    input: [
      {
        role: "user",
        content: [
          { type: "input_text", text: MEAL_RECOGNITION_USER_PROMPT },
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
        name: "meal_recognition",
        schema: mealRecognitionJsonSchema(),
        strict: true,
      },
    },
    store: false,
  });

  if (!response.output_text) throw new Error("OpenAI returned no meal recognition output.");
  const recognition = mealRecognitionSchema.parse(JSON.parse(response.output_text) as unknown);
  return {
    recognition,
    rawModelJson: response.output_text,
    requestId: response.id ?? null,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
