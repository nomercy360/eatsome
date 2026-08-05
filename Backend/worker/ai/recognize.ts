import type { RecognitionProvider, RecognitionRequest } from "../../src/contracts";
import { recognitionProviders } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { requestAnthropicRecognition } from "./anthropic";
import { requestGeminiRecognition } from "./gemini";
import { requestOpenAIRecognition } from "./openai";
import { requestQwenRecognition } from "./qwen";
import { productionSpec, type RecognitionSpec } from "./spec";
import type { ProviderRecognition } from "./types";

/**
 * Which vendor answers, and with what.
 *
 * The request may name one so a device can run its own comparison through the
 * proxy; otherwise the deployment's default stands. Both are held to the same
 * prompt and the same parsed contract, and the model id ends up on the
 * recognition row — which is also what keeps the cache from serving one
 * provider's answer for the other's question.
 */
export function resolveProvider(env: Env, requested?: RecognitionProvider): RecognitionProvider {
  const provider = requested ?? env.RECOGNITION_PROVIDER ?? "openai";
  if (!recognitionProviders.includes(provider)) {
    throw new HttpError(400, `Unknown recognition provider: ${provider}`);
  }
  return provider;
}

const models: Record<RecognitionProvider, (env: Env) => string> = {
  openai: (env) => env.OPENAI_RECOGNITION_MODEL,
  gemini: (env) => env.GEMINI_RECOGNITION_MODEL,
  anthropic: (env) => env.ANTHROPIC_RECOGNITION_MODEL,
  qwen: (env) => env.QWEN_RECOGNITION_MODEL,
};

const keys: Record<RecognitionProvider, (env: Env) => string | undefined> = {
  openai: (env) => env.OPENAI_API_KEY,
  gemini: (env) => env.GEMINI_API_KEY,
  anthropic: (env) => env.ANTHROPIC_API_KEY,
  qwen: (env) => env.QWEN_API_KEY,
};

export const keyVariableFor: Record<RecognitionProvider, string> = {
  openai: "OPENAI_API_KEY",
  gemini: "GEMINI_API_KEY",
  anthropic: "ANTHROPIC_API_KEY",
  qwen: "QWEN_API_KEY",
};

export function modelFor(env: Env, provider: RecognitionProvider): string {
  return models[provider](env);
}

export function apiKeyFor(env: Env, provider: RecognitionProvider): string | undefined {
  return keys[provider](env);
}

export function requestMealRecognition(
  env: Env,
  input: RecognitionRequest,
  provider: RecognitionProvider,
  spec: RecognitionSpec = productionSpec(input.note),
): Promise<ProviderRecognition> {
  if (provider === "gemini") return requestGeminiRecognition(env, input, spec);
  if (provider === "anthropic") return requestAnthropicRecognition(env, input, spec);
  if (provider === "qwen") return requestQwenRecognition(env, input, spec);
  return requestOpenAIRecognition(env, input, spec);
}
