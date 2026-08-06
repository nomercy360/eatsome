import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { HttpError } from "./http-error";
import { type Counters, enforcePaidRecognitionFairness, enforceRecognitionLimits } from "./limits";

const counters = (global: number, mine: number): Counters => ({
  today: async () => global,
  todayFor: async () => mine,
});
const env = (over: Partial<Record<string, unknown>> = {}): Env =>
  ({
    RECOGNITIONS_PER_DAY: "400",
    RECOGNITIONS_PER_DEVICE_PER_DAY: "40",
    RECOGNITION_LIMIT: { limit: async () => ({ success: true }) },
    ...over,
  }) as unknown as Env;

describe("recognition limits", () => {
  const anyone = "friend:0198F222AADB7E008000ABCDEF01";

  it("stops a burst before it reaches a paid API", async () => {
    const burst = env({ RECOGNITION_LIMIT: { limit: async () => ({ success: false }) } });
    await expect(enforceRecognitionLimits(burst, anyone)).rejects.toThrow(HttpError);
  });

  it("checks one friend's daily fairness only after a cache miss", async () => {
    await expect(
      enforcePaidRecognitionFairness(
        env(),
        "device:0198F222AADB7E008000ABCDEF01",
        counters(50, 40),
      ),
    ).rejects.toThrow(/day's worth/);
  });

  it("leaves the global money reservation to the post-cache budget ledger", async () => {
    await expect(enforceRecognitionLimits(env(), anyone)).resolves.toBeUndefined();
  });

  it("treats a ceiling of zero as no ceiling", async () => {
    const off = env({ RECOGNITIONS_PER_DAY: "0", RECOGNITIONS_PER_DEVICE_PER_DAY: "0" });
    await expect(
      enforcePaidRecognitionFairness(off, "device:anyone", counters(9e9, 9e9)),
    ).resolves.toBeUndefined();
  });
});
