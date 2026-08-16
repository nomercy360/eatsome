export type Env = {
  DB: D1Database;
  /** Private bucket. Only `media/` lives in it: the exact model-input bytes. */
  MEDIA: R2Bucket;
  GEMINI_API_KEY: string;
  /** `anonymous` enables session-backed multi-account production; anything
   *  else pins the deployment to one configured account and disables sign-in. */
  ACCOUNT_ID: string;
  /**
   * Every `aud` this deployment accepts in a Sign in with Apple token: the iOS
   * bundle id, plus a Services ID if a web flow is ever added. Comma separated.
   * Empty means Apple sign-in is refused with a 503 rather than accepted with
   * no audience check — an unset allowlist that matched everything would take a
   * token minted for a different app and treat its `sub` as one of our users.
   */
  APPLE_CLIENT_IDS: string;
  GEMINI_RECOGNITION_MODEL: string;
  GEMINI_THINKING_LEVEL: string;
  /** e.g. `MEDIA_RESOLUTION_HIGH`. Empty leaves Gemini's own default. */
  GEMINI_MEDIA_RESOLUTION: string;
  /**
   * `on` hands the recognition call Google Search as an available tool.
   *
   * Not a lookup and not a citation: the model decides whether to search, and
   * `generateContent` returns no grounding metadata beside a response schema,
   * so what comes back is the same contract with better numbers on branded
   * food. Measured on a Subway JP footlong: 845 and 865 kcal ungrounded
   * against a published 698, 700 and 697 grounded. Free on food nobody
   * published — an ordinary home meal performs no search at all.
   */
  RECOGNITION_SEARCH: string;
  /** Global ceiling across every caller, because the rate limiter is per-colo
   *  and a proxy in front of a paid model API needs a bound in money, not in
   *  requests per location. */
  RECOGNITIONS_PER_DAY: string;
  /** Per account, for fairness between honest callers. */
  RECOGNITIONS_PER_DEVICE_PER_DAY: string;
  RECOGNITION_LIMIT: RateLimit;
  SYNC_LIMIT: RateLimit;
};
