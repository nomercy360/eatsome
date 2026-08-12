import { describe, expect, it } from "vitest";
import { bearerToken } from "./auth";

describe("bearer authentication", () => {
  it("accepts one well-formed bearer token", () => {
    expect(bearerToken("Bearer secret-value")).toBe("secret-value");
    expect(bearerToken("Basic secret-value")).toBeNull();
    expect(bearerToken("Bearer two tokens")).toBeNull();
  });
});
