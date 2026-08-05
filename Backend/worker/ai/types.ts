import type { MealRecognition } from "../../src/contracts";

/** What every provider returns, so the caller never learns which one it was. */
export type ProviderRecognition = {
  recognition: MealRecognition;
  rawModelJson: string;
  requestId: string | null;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
};
