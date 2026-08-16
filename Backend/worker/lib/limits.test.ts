import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { deviceIdFor } from "./auth";
import { HttpError } from "./http-error";
import {
  type Counters,
  enforcePaidRecognitionFairness,
  enforceRecognitionLimits,
  enforceSyncLimits,
} from "./limits";

const request = (headers: Record<string, string>) =>
  new Request("https://example.com", { headers });
const counters = (mine: number): Counters => ({ todayFor: async () => mine });
const env = (over: Partial<Record<string, unknown>> = {}): Env =>
  ({
    RECOGNITIONS_PER_DAY: "400",
    RECOGNITIONS_PER_DEVICE_PER_DAY: "40",
    RECOGNITION_LIMIT: { limit: async () => ({ success: true }) },
    SYNC_LIMIT: { limit: async () => ({ success: true }) },
    ...over,
  }) as unknown as Env;

const ACCOUNT = "acct:0198f222-aadb-7e00-8000-abcdef012345";

describe("the device id is a label", () => {
  it("reads the id the app generated", () => {
    expect(deviceIdFor(request({ "X-Device-Id": "0198F222AADB7E008000ABCDEF01" }))).toBe(
      "0198F222AADB7E008000ABCDEF01",
    );
  });

  it("calls a caller that offers none, or offers nonsense, unknown", () => {
    // It used to fall back to `ip:<address>`, which was a partition key and
    // therefore a place rows could land — and an IP changes when the phone
    // changes network, so those rows became invisible to the same device
    // forever. Nothing is keyed on this any more, so an absent id is a blank
    // label rather than a second identity.
    expect(deviceIdFor(request({ "CF-Connecting-IP": "1.2.3.4" }))).toBe("unknown");
    expect(deviceIdFor(request({ "X-Device-Id": "'; DROP TABLE" }))).toBe("unknown");
  });
});

describe("recognition limits", () => {
  it("stops a burst before it reaches a paid API", async () => {
    const burst = env({ RECOGNITION_LIMIT: { limit: async () => ({ success: false }) } });
    await expect(enforceRecognitionLimits(burst, ACCOUNT)).rejects.toThrow(HttpError);
  });

  it("keys every layer on the verified account, never on the header", async () => {
    // A quota attached to a header the caller writes is a quota the caller can
    // reset by editing it. The account comes from a session whose digest is in
    // D1, so it cannot be chosen.
    const keys: string[] = [];
    const spying = env({
      RECOGNITION_LIMIT: {
        limit: async ({ key }: { key: string }) => {
          keys.push(key);
          return { success: true };
        },
      },
      SYNC_LIMIT: {
        limit: async ({ key }: { key: string }) => {
          keys.push(key);
          return { success: true };
        },
      },
    });
    await enforceRecognitionLimits(spying, ACCOUNT);
    await enforceSyncLimits(spying, ACCOUNT);
    expect(keys).toEqual([ACCOUNT, ACCOUNT]);
  });

  it("checks one account's daily fairness only after a cache miss", async () => {
    await expect(enforcePaidRecognitionFairness(env(), ACCOUNT, counters(40))).rejects.toThrow(
      /day's worth/,
    );
  });

  it("lets an ordinary request through", async () => {
    await expect(enforceRecognitionLimits(env(), ACCOUNT)).resolves.toBeUndefined();
    await expect(
      enforcePaidRecognitionFairness(env(), ACCOUNT, counters(3)),
    ).resolves.toBeUndefined();
  });

  it("treats a ceiling of zero as no ceiling", async () => {
    const off = env({ RECOGNITIONS_PER_DAY: "0", RECOGNITIONS_PER_DEVICE_PER_DAY: "0" });
    await expect(
      enforcePaidRecognitionFairness(off, ACCOUNT, counters(9e9)),
    ).resolves.toBeUndefined();
  });
});
