import { and, eq } from "drizzle-orm";
import type { MealRecognition, RecognitionRequest } from "../../src/contracts";
import { ATWATER_TOLERANCE, atwaterFailures, normalizePanels } from "../../src/contracts";
import { askGemini } from "../ai/gemini";
import { decodeBase64Image, sha256Hex } from "../ai/image";
import { MEAL_PROMPT_VERSION } from "../ai/prompt";
import { recognitionSpec } from "../ai/spec";
import { createDb } from "../db/client";
import { recognitions } from "../db/schema";
import type { Env } from "../env";
import { releaseRecognition, reserveRecognition } from "../lib/budget";
import { HttpError } from "../lib/http-error";
import { enforcePaidRecognitionFairness } from "../lib/limits";
import { ensureMediaObject } from "./media";

export type RecognitionResponse = {
  recognition: MealRecognition;
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
 * replays whatever this covers.
 *
 * Every field is tagged and NUL-separated before hashing, always. A bare
 * photograph used to short-circuit to its own hash — a compatibility shortcut
 * for rows written before text meals existed — and there are no such rows any
 * more, so what the shortcut bought was one special case in the one function
 * whose whole job is to keep two different questions apart.
 *
 * The market is in here and it is not a small addition: with search on,
 * "subway footlong" asked from Japan and asked from the United States are
 * questions with answers 500 kcal apart. Leaving it out would serve one
 * country's sandwich to the other and call it a cache hit.
 */
export async function inputFingerprint(input: {
  photoHash?: string | null;
  note?: string | null;
  said?: string | null;
  market?: string | null;
}): Promise<string> {
  const photoHash = input.photoHash?.toLowerCase() ?? "";
  const note = input.note?.trim() ?? "";
  const said = input.said?.trim() ?? "";
  const market = input.market?.trim().toUpperCase() ?? "";
  const NUL = String.fromCharCode(0);
  return sha256Hex(
    new TextEncoder().encode(
      `photo:${photoHash}${NUL}note:${note}${NUL}said:${said}${NUL}market:${market}`,
    ),
  );
}

/**
 * The country Cloudflare resolved the caller to.
 *
 * It goes into the model's turn as the weakest evidence there is, and it is
 * worth more than the rest of the prompt on branded food: "subway american
 * clubhouse footlong" asked with no country came back 1216 kcal, correctly, for
 * the American sandwich. Told the phone is in Japan the same words return 699
 * against a published 698. Nobody names their own country when typing what they
 * ate, so the request has to supply it.
 */
export function callerMarket(request: Request): string | null {
  // Both, because they disagree about when they exist. `cf.country` is absent
  // in local development, and the header is absent from a request that did not
  // come through the edge — reading only one of them is how this returned null
  // for every meal on the first end-to-end run. Cloudflare overwrites the header
  // at the edge, so a client cannot use it to claim a market in production.
  const header = request.headers.get("CF-IPCountry");
  const country = header ?? (request as { cf?: { country?: string } }).cf?.country;
  return typeof country === "string" && /^[A-Z]{2}$/.test(country) ? country : null;
}

/**
 * The self-check, where anyone can see it.
 *
 * `protein × 4 + carbohydrate × 4 + fat × 9 + alcohol × 7` against `kcal` is
 * the only check available with no table to compare against, and until now it
 * existed only in tests and in the prompt — which means it was checked against
 * fixtures and asked of the model, and never once looked at in production. A
 * warning rather than a refusal: the figures are still the best answer there
 * is, and a meal thrown away for failing arithmetic is a meal the person has to
 * log again by hand.
 */
function warnOnAtwater(recognition: MealRecognition, model: string, promptVersion: string): void {
  const failures = atwaterFailures(recognition);
  if (failures.length === 0) return;
  console.warn(
    `atwater: ${failures.length} of this answer's foods disagree with their own energy by more than ${Math.round(
      ATWATER_TOLERANCE * 100,
    )}% (${model}, ${promptVersion}) — ${failures
      .map((f) => `${f.dish}/${f.label} ${Math.round(f.delta * 100)}%`)
      .join(", ")}`,
  );
}

export async function recognizeMeal(
  env: Env,
  accountId: string,
  input: RecognitionRequest,
  market: string | null = null,
): Promise<RecognitionResponse> {
  if (input.imageBase64 && input.mimeType && input.photoHash) {
    const bytes = decodeBase64Image(input.imageBase64);
    const actualHash = await sha256Hex(bytes);
    if (actualHash !== input.photoHash.toLowerCase()) {
      throw new HttpError(400, "photoHash does not match the uploaded image bytes.");
    }

    // Storage is the first side effect. A provider failure or a cancelled
    // confirm sheet still leaves the exact model input available for a refine.
    const media = await ensureMediaObject(env, accountId, actualHash, input.mimeType, bytes);
    return recognizeInput(env, accountId, input, media.objectKey, market);
  }

  // A described meal: no bytes to decode, no hash to verify, nothing to put in
  // R2. The words still cache, because they are what the fingerprint covers.
  return recognizeInput(env, accountId, input, null, market);
}

async function recognizeInput(
  env: Env,
  accountId: string,
  input: RecognitionRequest,
  photoKey: string | null,
  market: string | null,
): Promise<RecognitionResponse> {
  const actualHash = input.photoHash?.toLowerCase() ?? null;
  const model = env.GEMINI_RECOGNITION_MODEL;
  const fingerprint = await inputFingerprint({ ...input, market });

  const db = createDb(env.DB);
  // The model is part of the key, so a prompt or model change costs a real call
  // rather than replaying an answer produced by a different question.
  const where = and(
    eq(recognitions.accountId, accountId),
    eq(recognitions.inputFingerprint, fingerprint),
    eq(recognitions.promptVersion, MEAL_PROMPT_VERSION),
    eq(recognitions.model, model),
  );
  const cached = await db.query.recognitions.findFirst({ where });
  if (cached) return response(cached, photoKey, true);

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

  let result: Awaited<ReturnType<typeof askGemini<MealRecognition>>>;
  try {
    const turn = { ...input, market };
    result = await askGemini(env, turn, recognitionSpec(turn));
  } catch (error) {
    // A failed call spent nothing, so it should not close the service.
    await releaseRecognition(env, ceiling);
    throw error;
  }
  warnOnAtwater(result.value, model, MEAL_PROMPT_VERSION);

  const row: typeof recognitions.$inferInsert = {
    id: crypto.randomUUID(),
    accountId,
    photoHash: actualHash,
    inputFingerprint: fingerprint,
    promptVersion: MEAL_PROMPT_VERSION,
    model,
    result: normalizePanels(result.value),
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
