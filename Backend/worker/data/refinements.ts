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

  const provider = resolveProvider(env, input.provider);
  await enforcePaidRecognitionFairness(env, accountId);
  const ceiling = Number(env.RECOGNITIONS_PER_DAY || 0);
  if (!(await reserveRecognition(env, ceiling))) {
    throw new HttpError(
      503,
      "Recognition is closed for today. This is a spending cap, not an outage.",
    );
  }

  const request: RecognitionRequest = {
    provider,
    photoHash,
    mimeType: stored.media.mimeType as RecognitionRequest["mimeType"],
    imageBase64: encodeBase64Image(stored.bytes),
    note: input.note,
  };
  try {
    const result = await requestMealRecognition(env, request, provider, revisionSpec(input));
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
