import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";
import { productionSpec } from "./spec";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v16.md");

describe("meal recognition prompt", () => {
  it("matches the file it was generated from", () => {
    // The app and the proxy each used to hold their own copy, and within a day
    // the proxy was two rules behind while both reported the same version.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v16-2026-08-07");
  });

  it("is the version the deployment stamps and keys its cache on", () => {
    // MEAL_PROMPT_VERSION reaches the Worker as a var, while the prompt text
    // comes from the generated constant. Let those disagree and answers to the
    // new prompt are cached under the old key, and every eval row names a
    // prompt that did not produce it — which is invisible in the data.
    const wrangler = readFileSync(join(import.meta.dirname, "../../wrangler.jsonc"), "utf8");
    const deployed = /"MEAL_PROMPT_VERSION":\s*"([^"]+)"/.exec(wrangler)?.[1];
    expect(deployed).toBe(MEAL_PROMPT_VERSION);
  });

  it("asks for weight once, and says nothing multiplies it", () => {
    // The quantity used to be three numbers that multiplied — dish count, dish
    // size, ingredient portion — and a model that saw one large bowl said so at
    // two levels, which compounded into 126 g of protein for a single ramen. On
    // 220 weighed dishes the flat weight beat the ladder by 11 points of median
    // error, so the prompt now asks for one absolute number and promises, twice,
    // that nothing is applied on top of it.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("It is ABSOLUTE");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("across every serving in the photograph");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Nothing multiplies `grams`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("so do not divide by them either");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("never multiplied into them");
    // Weight is asked for, energy and the other macros still are not.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Never estimate calories");
    // Two bananas and an apple are two dishes; a cut fruit plate is one.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Separate discrete countable things");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("mixed fruit plate");
  });

  it("gives every transcribed figure a unit, and does no arithmetic to get one", () => {
    // `carbohydrate: 1` is true per 100ml of a Monster and wrong by 3.55x for
    // the can. A number without its basis cannot be used at all.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("do no arithmetic of any kind");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("not salt into sodium");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("not per-100ml into per-can");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("a panel with figures and no basis is worse");
    // The band shortcut is gone: it let caffeine come from the warning band and
    // the macros from the table, and one `basis` cannot describe two units.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("One table, one basis, every field from it");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("converting between them is not your job");
  });

  it("allows a figure it cannot read to come back absent", () => {
    // A fabricated number stored where confirmed values live is worse than no
    // number, because the field's only value is that it is the trustworthy one.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Transcribe only");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("every field is null");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("a plausible one is not");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("The panel does not replace them");
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

  it("fences a person's note in the same user turn as the photo", () => {
    const prompt = productionSpec("  fried in butter  ").userPrompt;
    expect(prompt).toContain('"""\nfried in butter\n"""');
    expect(productionSpec().userPrompt).not.toContain('"""');
  });
});
