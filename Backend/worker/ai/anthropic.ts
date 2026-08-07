import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { parseFor, productionSpec, type RecognitionSpec } from "./spec";
import { hasImage, type ProviderInput, type ProviderRecognition } from "./types";

const ENDPOINT = "https://api.anthropic.com/v1/messages";
const VERSION = "2023-06-01";

/**
 * Claude has no `response_format`, so structured output goes through a tool the
 * model is forced to call. That is more reliable than asking for JSON in prose:
 * the arguments are schema-validated on the way out, and there is no prelude to
 * strip before parsing.
 */
const TOOL_NAME = "record_meal";

type AnthropicResponse = {
  content?: Array<{ type: string; name?: string; input?: unknown; text?: string }>;
  stop_reason?: string;
  usage?: { input_tokens?: number; output_tokens?: number };
  error?: { message?: string };
};

export async function requestAnthropicRecognition(
  env: Env,
  input: ProviderInput,
  spec: RecognitionSpec = productionSpec(),
): Promise<ProviderRecognition> {
  const startedAt = Date.now();
  const budget = Number(env.ANTHROPIC_THINKING_BUDGET || 0);
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": VERSION,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: env.ANTHROPIC_RECOGNITION_MODEL,
      max_tokens: budget > 0 ? budget + 2048 : 2048,
      ...(budget > 0 ? { thinking: { type: "enabled", budget_tokens: budget } } : {}),
      system: spec.systemPrompt,
      tools: [
        {
          name: TOOL_NAME,
          description: "Record the food groups and weights visible in the photograph.",
          input_schema: spec.jsonSchema,
        },
      ],
      // Anthropic refuses extended thinking alongside a forced tool call, so a
      // thinking budget costs the guarantee that the tool is used at all. That
      // is a real trade — schema compliance against deliberation — and the eval
      // is where it gets decided rather than assumed.
      tool_choice: budget > 0 ? { type: "auto" } : { type: "tool", name: TOOL_NAME },
      messages: [
        {
          role: "user",
          content: [
            ...(hasImage(input)
              ? [
                  {
                    type: "image",
                    source: { type: "base64", media_type: input.mimeType, data: input.imageBase64 },
                  },
                ]
              : []),
            { type: "text", text: spec.userPrompt },
          ],
        },
      ],
    }),
  });

  const body = (await response.json()) as AnthropicResponse;
  if (!response.ok) {
    throw new HttpError(
      502,
      `Anthropic returned ${response.status}: ${body.error?.message ?? "no body"}`,
    );
  }
  // A forced tool call that stopped for length is a partial meal, and a partial
  // meal that still parses silently drops food.
  if (body.stop_reason && !["tool_use", "end_turn", "stop_sequence"].includes(body.stop_reason)) {
    throw new HttpError(502, `Anthropic stopped early (${body.stop_reason}).`);
  }

  const call = body.content?.find((block) => block.type === "tool_use" && block.name === TOOL_NAME);
  if (!call?.input) throw new HttpError(502, "Anthropic returned no meal recognition output.");

  const rawModelJson = JSON.stringify(call.input);
  return {
    recognition: parseFor(spec)(call.input),
    rawModelJson,
    requestId: response.headers.get("request-id"),
    inputTokens: body.usage?.input_tokens ?? 0,
    outputTokens: body.usage?.output_tokens ?? 0,
    latencyMs: Date.now() - startedAt,
  };
}
