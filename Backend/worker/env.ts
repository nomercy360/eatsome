import type { RecognitionProvider } from "../src/contracts";

export type Env = {
  DB: D1Database;
  OPENAI_API_KEY: string;
  GEMINI_API_KEY: string;
  ANTHROPIC_API_KEY: string;
  QWEN_API_KEY: string;
  EATSOME_API_TOKEN: string;
  ACCOUNT_ID: string;
  OPENAI_RECOGNITION_MODEL: string;
  GEMINI_RECOGNITION_MODEL: string;
  ANTHROPIC_RECOGNITION_MODEL: string;
  QWEN_RECOGNITION_MODEL: string;
  // Any OpenAI-compatible host: DashScope, QwenCloud, OpenRouter.
  QWEN_BASE_URL: string;
  // Used when a request does not name one.
  RECOGNITION_PROVIDER: RecognitionProvider;
  MEAL_PROMPT_VERSION: string;
};
