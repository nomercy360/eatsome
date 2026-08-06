import { describe, expect, it } from "vitest";
import {
  accountForDevice,
  accountForInviteToken,
  bearerToken,
  requireStableAccount,
  tokenDigest,
  tokensMatch,
} from "./auth";

describe("bearer authentication", () => {
  it("accepts one well-formed bearer token", () => {
    expect(bearerToken("Bearer secret-value")).toBe("secret-value");
    expect(bearerToken("Basic secret-value")).toBeNull();
    expect(bearerToken("Bearer two tokens")).toBeNull();
  });

  it("compares token digests", async () => {
    await expect(tokensMatch("same", "same")).resolves.toBe(true);
    await expect(tokensMatch("same", "different")).resolves.toBe(false);
  });

  it("produces the stable SHA-256 stored by the invite tool", async () => {
    await expect(tokenDigest("friend-token")).resolves.toBe(
      "621913ae8c24bbfb905baca90b0eeaa4a47b34aaa5fd75ff81c7e65a185d308a",
    );
  });

  it("resolves only an active token to its account", async () => {
    const expected = await tokenDigest("eat_dev_secret");
    const database = {
      prepare: () => ({
        bind: (tokenHash: string) => ({
          first: async () => (tokenHash === expected ? { accountId: "friend:0198-example" } : null),
        }),
      }),
    } as unknown as D1Database;
    await expect(accountForInviteToken(database, "eat_dev_secret")).resolves.toBe(
      "friend:0198-example",
    );
    await expect(accountForInviteToken(database, "wrong")).resolves.toBeNull();
  });

  it("retains the device partition for the migration-only owner token", () => {
    const request = new Request("https://example.com", {
      headers: { "X-Device-Id": "0198F222AADB7E008000ABCDEF01" },
    });
    expect(accountForDevice(request)).toBe("device:0198F222AADB7E008000ABCDEF01");
  });

  it("does not accept an IP address as a stored-data account", () => {
    expect(() => requireStableAccount("ip:1.2.3.4")).toThrow(/X-Device-Id/);
  });
});
