import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { accountForDevice } from "./auth";
import { HttpError } from "./http-error";
import { type Counters, enforceRecognitionLimits } from "./limits";

const request = (headers: Record<string, string>) =>
  new Request("https://example.com", { headers });
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

describe("who is calling, with no login", () => {
  it("keys on the device id the app generated", () => {
    expect(accountForDevice(request({ "X-Device-Id": "0198F222AADB7E008000ABCDEF01" }))).toBe(
      "device:0198F222AADB7E008000ABCDEF01",
    );
  });

  it("falls back to the IP when no id is offered", () => {
    // Sharing one bucket with every other anonymous caller is the incentive.
    expect(accountForDevice(request({ "CF-Connecting-IP": "1.2.3.4" }))).toBe("ip:1.2.3.4");
  });

  it("ignores an id that could not have come from the app", () => {
    expect(accountForDevice(request({ "X-Device-Id": "'; DROP TABLE" }))).toBe("ip:unknown");
  });
});

describe("recognition limits", () => {
  const anyone = request({ "X-Device-Id": "0198F222AADB7E008000ABCDEF01" });

  it("stops a burst before it reaches a paid API", async () => {
    const burst = env({ RECOGNITION_LIMIT: { limit: async () => ({ success: false }) } });
    await expect(enforceRecognitionLimits(burst, anyone, counters(0, 0))).rejects.toThrow(
      HttpError,
    );
  });

  it("stops one device spending everyone's day", async () => {
    await expect(enforceRecognitionLimits(env(), anyone, counters(50, 40))).rejects.toThrow(
      /day's worth/,
    );
  });

  it("stops the whole service at the spending cap, however it was spread", async () => {
    // The rate limiter is per-colo, so this is the only layer that bounds money.
    await expect(enforceRecognitionLimits(env(), anyone, counters(400, 1))).rejects.toThrow(
      /spending cap/,
    );
  });

  it("lets an ordinary request through", async () => {
    await expect(enforceRecognitionLimits(env(), anyone, counters(12, 3))).resolves.toBe(
      "device:0198F222AADB7E008000ABCDEF01",
    );
  });

  it("treats a ceiling of zero as no ceiling", async () => {
    const off = env({ RECOGNITIONS_PER_DAY: "0", RECOGNITIONS_PER_DEVICE_PER_DAY: "0" });
    await expect(enforceRecognitionLimits(off, anyone, counters(9e9, 9e9))).resolves.toBeDefined();
  });
});
