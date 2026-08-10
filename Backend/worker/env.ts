import type { RecognitionProvider } from "../src/contracts";

export type Env = {
  DB: D1Database;
  /** Private bucket. `media/` and `corpus/` have deliberately separate lifecycles. */
  MEDIA: R2Bucket;
  OPENAI_API_KEY: string;
  GEMINI_API_KEY: string;
  ANTHROPIC_API_KEY: string;
  QWEN_API_KEY: string;
  OPENROUTER_API_KEY: string;
  /** Mints short-lived transcription keys; the real key never reaches a device. */
  SONIOX_API_KEY: string;
  EATSOME_API_TOKEN: string;
  /** `anonymous` means "partition by caller"; anything else pins the whole
   *  deployment to one account and disables sign-in. */
  ACCOUNT_ID: string;
  /**
   * Every `aud` this deployment accepts in a Sign in with Apple token: the iOS
   * bundle id, plus a Services ID if a web flow is ever added. Comma separated.
   * Empty means Apple sign-in is refused with a 503 rather than accepted with
   * no audience check — an unset allowlist that matched everything would take a
   * token minted for a different app and treat its `sub` as one of our users.
   */
  APPLE_CLIENT_IDS: string;
  /** The same, for Google's OAuth client ids. Empty until a client exists. */
  GOOGLE_CLIENT_IDS: string;
  OPENAI_RECOGNITION_MODEL: string;
  GEMINI_RECOGNITION_MODEL: string;
  ANTHROPIC_RECOGNITION_MODEL: string;
  QWEN_RECOGNITION_MODEL: string;
  OPENROUTER_RECOGNITION_MODEL: string;
  // Any OpenAI-compatible host: DashScope, QwenCloud, OpenRouter.
  QWEN_BASE_URL: string;
  OPENROUTER_BASE_URL: string;
  // Used when a request does not name one.
  RECOGNITION_PROVIDER: RecognitionProvider;
  // Reasoning budget per provider. Empty means the provider's own default,
  // which is not the same thing across vendors — Anthropic ships with extended
  // thinking off while Gemini and OpenAI take an explicit level.
  OPENAI_REASONING_EFFORT: string;
  /** `high` tiles the image so small print survives; `low` is a flat 85 tokens
   *  and about 512px, which cannot read a label. Empty means `high`. */
  OPENAI_IMAGE_DETAIL: string;
  GEMINI_THINKING_LEVEL: string;
  /** e.g. `MEDIA_RESOLUTION_HIGH`. Empty leaves Gemini's own default. */
  GEMINI_MEDIA_RESOLUTION: string;
  /** Tokens; 0 or empty leaves extended thinking off. */
  ANTHROPIC_THINKING_BUDGET: string;
  /** "true" turns Qwen's thinking mode on. */
  QWEN_ENABLE_THINKING: string;
  MEAL_PROMPT_VERSION: string;
  /** Global ceiling across every caller, because the rate limiter is per-colo
   *  and a proxy in front of paid model APIs needs a bound in money, not in
   *  requests per location. */
  RECOGNITIONS_PER_DAY: string;
  /** Per device, for fairness between honest callers. */
  RECOGNITIONS_PER_DEVICE_PER_DAY: string;
  RECOGNITION_LIMIT: RateLimit;
  SYNC_LIMIT: RateLimit;
};
