import { and, eq } from "drizzle-orm";
import type { MealRecognition, RecognitionRequest } from "../../src/contracts";
import { decodeBase64Image, sha256Hex } from "../ai/image";
import { modelFor, requestMealRecognition, resolveProvider } from "../ai/recognize";
import { createDb } from "../db/client";
import { recognitions } from "../db/schema";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";

export type RecognitionResponse = {
  recognition: MealRecognition;
  rawModelJSON: string;
  promptVersion: string;
  model: string;
  providerRequestId: string | null;
  cached: boolean;
};

function response(row: typeof recognitions.$inferSelect, cached: boolean): RecognitionResponse {
  return {
    recognition: row.result,
    rawModelJSON: row.rawModelJson,
    promptVersion: row.promptVersion,
    model: row.model,
    providerRequestId: row.providerRequestId,
    cached,
  };
}

export async function recognizeMeal(
  env: Env,
  accountId: string,
  input: RecognitionRequest,
): Promise<RecognitionResponse> {
  const bytes = decodeBase64Image(input.imageBase64);
  const actualHash = await sha256Hex(bytes);
  if (actualHash !== input.photoHash.toLowerCase()) {
    throw new HttpError(400, "photoHash does not match the uploaded image bytes.");
  }

  const provider = resolveProvider(env, input.provider);
  const model = modelFor(env, provider);

  const db = createDb(env.DB);
  // The model is part of the key, so asking the other provider about a photo
  // you have already sent costs a real call rather than replaying an answer
  // that came from somewhere else.
  const where = and(
    eq(recognitions.accountId, accountId),
    eq(recognitions.photoHash, actualHash),
    eq(recognitions.promptVersion, env.MEAL_PROMPT_VERSION),
    eq(recognitions.model, model),
  );
  const cached = await db.query.recognitions.findFirst({ where });
  if (cached) return response(cached, true);

  const result = await requestMealRecognition(env, input, provider);
  const row: typeof recognitions.$inferInsert = {
    id: crypto.randomUUID(),
    accountId,
    photoHash: actualHash,
    promptVersion: env.MEAL_PROMPT_VERSION,
    model,
    result: result.recognition,
    rawModelJson: result.rawModelJson,
    providerRequestId: result.requestId,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
    latencyMs: result.latencyMs,
    createdAt: new Date().toISOString(),
  };
  await db.insert(recognitions).values(row).onConflictDoNothing();

  const stored = await db.query.recognitions.findFirst({ where });
  if (!stored) throw new Error("Recognition completed but could not be persisted.");
  return response(stored, false);
}
