/**
 * What the model is given, which is less than the request.
 *
 * The picture is optional because a correction may not have one: a meal typed
 * in by hand has no photograph to reason about, and the person's own words are
 * then the entire input. The image part is omitted rather than sent empty — a
 * zero-length image is a decode error at the vendor, not an absent image.
 */
export type ProviderInput = {
  mimeType?: string;
  imageBase64?: string;
  /** The person describing the meal — the whole input when there is no image. */
  said?: string | null;
  /** The person annotating a photograph: what it cannot show. */
  note?: string | null;
  /**
   * ISO country the request came from, when the edge resolved one.
   *
   * Not part of the request the client sends and deliberately so — this is the
   * network's claim about where the phone is, not the person's claim about
   * where they ate. It reaches the model as the weakest evidence in the turn,
   * because on a branded product the market is worth more than everything else
   * put together: the same sandwich is 698 kcal in Japan and about 1200 in the
   * United States.
   */
  market?: string | null;
};

export function hasImage(input: ProviderInput): input is ProviderInput & {
  mimeType: string;
  imageBase64: string;
} {
  return Boolean(input.imageBase64 && input.mimeType);
}

/**
 * One question for the model, whole: what to ask, in what shape to answer, and
 * how to read the answer.
 *
 * Recognition and revision each build one of these and each owns all three
 * parts. They used to share a `RecognitionSpec` with an optional Gemini schema
 * and a `parseFor` function that switched on a schema *name* to decide which
 * Zod contract to apply — an indirection whose only job was to route two
 * callers to two parsers. Carrying the parser on the call itself makes the
 * type say what the string used to imply, and makes `askGemini` generic instead
 * of casting through `never`.
 */
export type ModelCall<T> = {
  systemPrompt: string;
  userPrompt: string;
  /** Gemini's OpenAPI subset, hand-written. See `geminiResponseSchema`. */
  responseSchema: Record<string, unknown>;
  parse: (value: unknown) => T;
};

/** What a model call returns, plus what it cost. */
export type ModelAnswer<T> = {
  value: T;
  rawModelJson: string;
  requestId: string | null;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
};
