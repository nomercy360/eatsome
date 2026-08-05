import type { RecognitionProvider, RecognitionRequest } from "../../src/contracts";
import { recognitionProviders } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { requestGeminiRecognition } from "./gemini";
import { requestOpenAIRecognition } from "./openai";
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

export function modelFor(env: Env, provider: RecognitionProvider): string {
  return provider === "gemini" ? env.GEMINI_RECOGNITION_MODEL : env.OPENAI_RECOGNITION_MODEL;
}

export function apiKeyFor(env: Env, provider: RecognitionProvider): string | undefined {
  return provider === "gemini" ? env.GEMINI_API_KEY : env.OPENAI_API_KEY;
}

export function requestMealRecognition(
  env: Env,
  input: RecognitionRequest,
  provider: RecognitionProvider,
): Promise<ProviderRecognition> {
  return provider === "gemini"
    ? requestGeminiRecognition(env, input)
    : requestOpenAIRecognition(env, input);
}
