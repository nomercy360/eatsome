import { describe, expect, it } from "vitest";
import { MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";

describe("meal recognition prompt", () => {
  it("contains the real-food failure rules", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("closest to the camera");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("other_meals_visible");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("miso soup contains legumes");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Every item carries alternatives");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("an empty list is the normal case");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("confidence");
  });
});
