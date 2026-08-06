import type { RecognitionRequest, RefinementRequest } from "../../src/contracts";
import { mealRevisionSchema } from "../../src/contracts";
import { encodeBase64Image } from "../ai/image";
import { modelFor, requestMealRecognition, resolveProvider } from "../ai/recognize";
import { revisionSpec } from "../ai/revision";
import type { Env } from "../env";
import { releaseRecognition, reserveRecognition } from "../lib/budget";
import { HttpError } from "../lib/http-error";
import { enforcePaidRecognitionFairness } from "../lib/limits";
import { getStoredMediaInput } from "./media";

export async function refineMeal(
  env: Env,
  accountId: string,
  photoHash: string,
  input: RefinementRequest,
) {
  const stored = await getStoredMediaInput(env, accountId, photoHash);
  if (!stored) throw new HttpError(404, "Stored model input not found.");

  return reviseWith(env, accountId, input, {
    mimeType: stored.media.mimeType as RecognitionRequest["mimeType"],
    imageBase64: encodeBase64Image(stored.bytes),
  });
}

/**
 * The same correction with no photograph behind it.
 *
 * A meal typed in by hand never had one, and a failed reading may never get
 * one, but the revision prompt was always mostly text: it works from the
 * current list and the person's own words, and the picture is corroboration. So
 * this is the identical call with the image part left off — not a second, lesser
 * prompt, which would make two ways to be wrong.
 */
export async function refineMealFromNote(env: Env, accountId: string, input: RefinementRequest) {
  return reviseWith(env, accountId, input, {});
}

async function reviseWith(
  env: Env,
  accountId: string,
  input: RefinementRequest,
  image: { mimeType?: string; imageBase64?: string },
) {
  const provider = resolveProvider(env, input.provider);
  await enforcePaidRecognitionFairness(env, accountId);
  const ceiling = Number(env.RECOGNITIONS_PER_DAY || 0);
  if (!(await reserveRecognition(env, ceiling))) {
    throw new HttpError(
      503,
      "Recognition is closed for today. This is a spending cap, not an outage.",
    );
  }

  try {
    const result = await requestMealRecognition(
      env,
      { ...image, note: input.note },
      provider,
      revisionSpec(input),
    );
    return {
      revision: mealRevisionSchema.parse(result.recognition),
      promptVersion: env.MEAL_PROMPT_VERSION,
      model: modelFor(env, provider),
      providerRequestId: result.requestId,
    };
  } catch (error) {
    await releaseRecognition(env, ceiling);
    throw error;
  }
}
