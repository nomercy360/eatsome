import type { MealRecognition } from "../../src/contracts";

/**
 * What a provider needs from the request, which is less than the request.
 *
 * The picture is optional because a correction may not have one: a meal typed
 * in by hand has no photograph to reason about, and the person's own words are
 * then the entire input. Every provider omits the image part rather than
 * sending an empty one — a zero-length image is a decode error at the vendor,
 * not an absent image.
 */
export type ProviderInput = {
  mimeType?: string;
  imageBase64?: string;
  /** The person describing the meal — the whole input when there is no image. */
  said?: string | null;
  /** The person annotating a photograph: what it cannot show. */
  note?: string | null;
};

export function hasImage(input: ProviderInput): input is ProviderInput & {
  mimeType: string;
  imageBase64: string;
} {
  return Boolean(input.imageBase64 && input.mimeType);
}

/** What every provider returns, so the caller never learns which one it was. */
export type ProviderRecognition = {
  recognition: MealRecognition;
  rawModelJson: string;
  requestId: string | null;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
};
