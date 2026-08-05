import { and, eq } from "drizzle-orm";
import type { MealRecognition, RecognitionRequest } from "../../src/contracts";
import { decodeBase64Image, sha256Hex } from "../ai/image";
import { requestMealRecognition } from "../ai/recognize";
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

  const db = createDb(env.DB);
  const where = and(
    eq(recognitions.accountId, accountId),
    eq(recognitions.photoHash, actualHash),
    eq(recognitions.promptVersion, env.MEAL_PROMPT_VERSION),
    eq(recognitions.model, env.OPENAI_RECOGNITION_MODEL),
  );
  const cached = await db.query.recognitions.findFirst({ where });
  if (cached) return response(cached, true);

  const provider = await requestMealRecognition(env, input);
  const row: typeof recognitions.$inferInsert = {
    id: crypto.randomUUID(),
    accountId,
    photoHash: actualHash,
    promptVersion: env.MEAL_PROMPT_VERSION,
    model: env.OPENAI_RECOGNITION_MODEL,
    result: provider.recognition,
    rawModelJson: provider.rawModelJson,
    providerRequestId: provider.requestId,
    inputTokens: provider.inputTokens,
    outputTokens: provider.outputTokens,
    latencyMs: provider.latencyMs,
    createdAt: new Date().toISOString(),
  };
  await db.insert(recognitions).values(row).onConflictDoNothing();

  const stored = await db.query.recognitions.findFirst({ where });
  if (!stored) throw new Error("Recognition completed but could not be persisted.");
  return response(stored, false);
}
