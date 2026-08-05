import { describe, expect, it } from "vitest";
import { bearerToken, tokensMatch } from "./auth";

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
});
