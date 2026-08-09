import { and, eq } from "drizzle-orm";
import type {
  MealRecognitionPayload,
  RecognitionRequest,
  RerunRecognitionRequest,
} from "../../src/contracts";
import { flattenDishes } from "../../src/contracts";
import { decodeBase64Image, encodeBase64Image, sha256Hex } from "../ai/image";
import { modelFor, requestMealRecognition, resolveProvider } from "../ai/recognize";
import { createDb } from "../db/client";
import { recognitions } from "../db/schema";
import type { Env } from "../env";
import { releaseRecognition, reserveRecognition } from "../lib/budget";
import { HttpError } from "../lib/http-error";
import { enforcePaidRecognitionFairness } from "../lib/limits";
import { ensureMediaObject, getStoredMediaInput } from "./media";

export type RecognitionResponse = {
  recognition: MealRecognitionPayload;
  rawModelJSON: string;
  promptVersion: string;
  model: string;
  providerRequestId: string | null;
  /** Null when the meal was described rather than photographed. */
  photoKey: string | null;
  cached: boolean;
};

function response(
  row: typeof recognitions.$inferSelect,
  photoKey: string | null,
  cached: boolean,
): RecognitionResponse {
  return {
    recognition: row.result,
    rawModelJSON: row.rawModelJson,
    promptVersion: row.promptVersion,
    model: row.model,
    providerRequestId: row.providerRequestId,
    photoKey,
    cached,
  };
}

/**
 * One fingerprint over everything the model was given, because the cache
 * replays whatever this covers. A bare photograph keys on its own hash, exactly
 * as every existing row does. As soon as any text is involved the fields are
 * tagged and NUL-separated before hashing: "fried in butter" said and "fried in
 * butter" noted are different questions about the same photo, and two typed
 * meals with no photograph must never collide just because neither has a hash —
 * that would silently serve one person's lentil soup as their oatmeal.
 */
export async function inputFingerprint(input: {
  photoHash?: string | null;
  note?: string | null;
  said?: string | null;
}): Promise<string> {
  const photoHash = input.photoHash?.toLowerCase() ?? "";
  const note = input.note?.trim() ?? "";
  const said = input.said?.trim() ?? "";
  if (photoHash && !note && !said) return photoHash;
  const NUL = String.fromCharCode(0);
  return sha256Hex(
    new TextEncoder().encode(`photo:${photoHash}${NUL}note:${note}${NUL}said:${said}`),
  );
}

export async function recognizeMeal(
  env: Env,
  accountId: string,
  input: RecognitionRequest,
): Promise<RecognitionResponse> {
  if (input.imageBase64 && input.mimeType && input.photoHash) {
    const bytes = decodeBase64Image(input.imageBase64);
    const actualHash = await sha256Hex(bytes);
    if (actualHash !== input.photoHash.toLowerCase()) {
      throw new HttpError(400, "photoHash does not match the uploaded image bytes.");
    }

    // Storage is the first side effect. A provider failure or a cancelled
    // confirm sheet still leaves the exact model input available for a re-run.
    const media = await ensureMediaObject(env, accountId, actualHash, input.mimeType, bytes);
    return recognizeInput(env, accountId, input, media.objectKey, false);
  }

  // A described meal: no bytes to decode, no hash to verify, nothing to put in
  // R2. The words still cache, because they are what the fingerprint covers.
  return recognizeInput(env, accountId, input, null, false);
}

export async function rerunRecognition(
  env: Env,
  accountId: string,
  photoHash: string,
  input: RerunRecognitionRequest,
): Promise<RecognitionResponse> {
  const stored = await getStoredMediaInput(env, accountId, photoHash);
  if (!stored) throw new HttpError(404, "Stored model input not found.");
  return recognizeInput(
    env,
    accountId,
    {
      provider: input.provider,
      note: input.note,
      photoHash,
      mimeType: stored.media.mimeType as RecognitionRequest["mimeType"],
      imageBase64: encodeBase64Image(stored.bytes),
    },
    stored.media.objectKey,
    input.refresh,
  );
}

async function recognizeInput(
  env: Env,
  accountId: string,
  input: RecognitionRequest,
  photoKey: string | null,
  refresh: boolean,
): Promise<RecognitionResponse> {
  const actualHash = input.photoHash?.toLowerCase() ?? null;
  const provider = resolveProvider(env, input.provider);
  const model = modelFor(env, provider);
  const fingerprint = await inputFingerprint(input);

  const db = createDb(env.DB);
  // The model is part of the key, so asking the other provider about a photo
  // you have already sent costs a real call rather than replaying an answer
  // that came from somewhere else.
  const where = and(
    eq(recognitions.accountId, accountId),
    eq(recognitions.inputFingerprint, fingerprint),
    eq(recognitions.promptVersion, env.MEAL_PROMPT_VERSION),
    eq(recognitions.model, model),
  );
  const cached = await db.query.recognitions.findFirst({ where });
  if (cached && !refresh) return response(cached, photoKey, true);

  await enforcePaidRecognitionFairness(env, accountId);

  // Only a miss costs anything, so only a miss is charged — and the charge is
  // taken before the call, not counted after it, because a count taken after
  // the fact cannot refuse anything.
  const ceiling = Number(env.RECOGNITIONS_PER_DAY || 0);
  if (!(await reserveRecognition(env, ceiling))) {
    // Deliberately not "try again shortly": the window is a day, and a client
    // that retries into it spends tomorrow's budget too.
    throw new HttpError(
      503,
      "Recognition is closed for today. This is a spending cap, not an outage.",
    );
  }

  let result: Awaited<ReturnType<typeof requestMealRecognition>>;
  try {
    result = await requestMealRecognition(env, input, provider);
  } catch (error) {
    // A failed call spent nothing, so it should not close the service.
    await releaseRecognition(env, ceiling);
    throw error;
  }
  const row: typeof recognitions.$inferInsert = {
    id: crypto.randomUUID(),
    accountId,
    photoHash: actualHash,
    inputFingerprint: fingerprint,
    promptVersion: env.MEAL_PROMPT_VERSION,
    model,
    result: flattenDishes(result.recognition),
    rawModelJson: result.rawModelJson,
    providerRequestId: result.requestId,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
    latencyMs: result.latencyMs,
    createdAt: new Date().toISOString(),
  };
  await db
    .insert(recognitions)
    .values(row)
    .onConflictDoUpdate({
      target: [
        recognitions.accountId,
        recognitions.inputFingerprint,
        recognitions.promptVersion,
        recognitions.model,
      ],
      set: {
        id: row.id,
        photoHash: row.photoHash,
        result: row.result,
        rawModelJson: row.rawModelJson,
        providerRequestId: row.providerRequestId,
        inputTokens: row.inputTokens,
        outputTokens: row.outputTokens,
        latencyMs: row.latencyMs,
        createdAt: row.createdAt,
      },
    });

  const stored = await db.query.recognitions.findFirst({ where });
  if (!stored) throw new Error("Recognition completed but could not be persisted.");
  return response(stored, photoKey, false);
}
