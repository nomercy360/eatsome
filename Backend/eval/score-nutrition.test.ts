import { describe, expect, it } from "vitest";
import { excludes } from "./score-nutrition";

/**
 * The exclusion decides which rows are compared against a published figure, so
 * a wrong match does not fail loudly — it quietly removes food and reports the
 * shortfall as a model error.
 */
describe("golden-case exclusions", () => {
  it("matches whole words, not substrings", () => {
    // The bug this test exists for. "tea" is inside "steamed", "steak" and
    // "oatmeal", and excluding a cup of tea would have dropped the rice.
    expect(excludes("steamed white rice", ["tea"])).toBe(false);
    expect(excludes("beef steak", ["tea"])).toBe(false);
    expect(excludes("oatmeal", ["tea"])).toBe(false);
    expect(excludes("green tea", ["tea"])).toBe(true);
    expect(excludes("tea", ["tea"])).toBe(true);
  });

  it("matches a phrase only when its words are adjacent and in order", () => {
    expect(excludes("miso soup", ["miso soup"])).toBe(true);
    expect(excludes("miso broth and seaweed", ["miso soup"])).toBe(false);
    // A model naming the same thing more fully is still the same thing.
    expect(excludes("soy marinated seasoned egg", ["seasoned egg"])).toBe(true);
  });

  it("ignores punctuation and case", () => {
    expect(excludes("Miso Soup (small)", ["miso soup"])).toBe(true);
  });

  it("excludes nothing when the list is empty", () => {
    expect(excludes("white rice", [])).toBe(false);
    expect(excludes("white rice", [""])).toBe(false);
  });
});
