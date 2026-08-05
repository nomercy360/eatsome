import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v5.md");

describe("meal recognition prompt", () => {
  it("matches the file it was generated from", () => {
    // The app and the proxy each used to hold their own copy, and within a day
    // the proxy was two rules behind while both reported the same version.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v5-2026-08-05");
  });

  it("contains the real-food failure rules", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("closest to the camera");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("other_meals_visible");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("miso soup contains legumes");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Every item carries `alternatives`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("an empty list is the normal case");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("confidence");
  });

  it("carries the rules the proxy was missing before the prompt became one file", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("what the photograph cannot show");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the rest is theirs too");
  });
});
