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
  EATSOME_API_TOKEN: string;
  ACCOUNT_ID: string;
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
  GEMINI_THINKING_LEVEL: string;
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
