import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import { productionSpec } from "./spec";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v19.md");
const revisionFile = join(import.meta.dirname, "../../../prompts/revision-v2.md");

describe("meal recognition prompt", () => {
  it("matches the file it was generated from", () => {
    // The app and the proxy each used to hold their own copy, and within a day
    // the proxy was two rules behind while both reported the same version.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v19-2026-08-10");
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
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("across every serving present");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Nothing multiplies `grams`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("so do not divide by it either");
    // Two bananas and an apple are two dishes; a cut fruit plate is one.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Separate discrete countable things");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("mixed fruit plate");
  });

  it("asks for exactly one quantity", () => {
    // v16 asked for grams AND a coarse portion AND a dish size, then had to
    // rank them: grams win, which made the other two tokens spent on an answer
    // nothing read and a chip in the UI that changed no quantity. Worse, one line
    // of v16 still said "Report food GROUPS and coarse PORTIONS only. Never
    // estimate calories, grams, or macronutrients" — a v10 rule that outlived
    // its prompt and sat eleven lines under the rule demanding a weight.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the ONLY quantity you report");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Every ingredient carries a weight");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("coarse PORTIONS");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`portion`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`size`");
    // Weight is asked for; energy and the other macros still are not.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Never estimate calories");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`grams` is the exception");
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

  it("covers a meal that arrives as words, honestly about what that means", () => {
    // v18's reason to exist. The weight rule is grounded differently per mode
    // and says so: read off the frame with a photograph, read off the words
    // without one — and the words rank, a stated figure above a count above a
    // size word. What it never becomes is a licence to estimate nutrients.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("typed or dictated");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the words are the entire input");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("absent, not implied");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("A stated weight or volume is a fact");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("never rounded to a rounder number");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "estimating from a description, not reading a photograph",
    );
    // Words about this meal beat pixels of it, in quantity and in content.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the words win");
    // A typed meal skipped nothing.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`other_meals_visible` is false");
    // A quoted label is transcription at one remove; a remembered one is not.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("a printed fact relayed");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("a remembered one is fabrication");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the sound of the description");
  });

  it("names food without steering the verdict", () => {
    // The recognition model reports what is on the plate. It must not be
    // steered toward a named eating pattern or a weekly outcome.
    // Nor does the framing get swapped for a friendlier one: "healthy",
    // "balanced" and "clean" are verdicts too, and a model told it is looking
    // for healthy food finds it.
    for (const verdict of [
      "Mediterranean",
      "MEDAS",
      "adherence",
      "healthy",
      "balanced",
      "clean eating",
    ]) {
      expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain(verdict);
    }
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("the food groups it is made of");
  });

  it("routes an unnamed cooking oil to the commoner oil, not to olive", () => {
    // Until the taxonomy had a second oil, the prompt's only home for an
    // invisible frying fat was `olive_oil`.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`vegetable_oil`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "`olive_oil` needs evidence that it was olive oil",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("a guess dressed as a reading");
    // And the two renamed groups are spelled the way the schema spells them.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`plant_fats`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`cooked_tomato_sauce`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("sofrito");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("healthy_fats");
  });

  it("fences a person's note in the same user turn as the photo", () => {
    const image = { mimeType: "image/jpeg", imageBase64: "aGVsbG8gdGhlcmUh" };
    const prompt = productionSpec({ ...image, note: "  fried in butter  " }).userPrompt;
    expect(prompt).toContain("What the photo cannot show");
    expect(prompt).toContain('"""\nfried in butter\n"""');
    expect(productionSpec(image).userPrompt).not.toContain('"""');
  });

  it("tells the model when the words are the entire input", () => {
    const typed = productionSpec({ said: "leftover lentil soup, big bowl" });
    expect(typed.userPrompt).toContain("There is no photograph");
    expect(typed.userPrompt).toContain('"""\nleftover lentil soup, big bowl\n"""');
    // A photographed meal keeps the camera opening; a caption rides along
    // without changing what the model is told it is looking at.
    const captioned = productionSpec({
      mimeType: "image/jpeg",
      imageBase64: "aGVsbG8gdGhlcmUh",
      said: "2 of this at 11 am",
    });
    expect(captioned.userPrompt).toContain("closest to the camera");
    expect(captioned.userPrompt).toContain('"""\n2 of this at 11 am\n"""');
    expect(captioned.userPrompt).not.toContain("There is no photograph");
  });

  it("never claims a note is about a photograph that does not exist", () => {
    const typed = productionSpec({ said: "porridge", note: "with honey" });
    expect(typed.userPrompt).not.toContain("What the photo cannot show");
    expect(typed.userPrompt).toContain('"""\nwith honey\n"""');
  });
});

describe("meal revision prompt", () => {
  it("matches the file it was generated from", () => {
    // It was a string literal here and a second one in MealRevision.swift, and
    // by the time anyone compared them they differed in three rules while both
    // claimed to be the same instructions — a model told two different things
    // about the same food, with nothing anywhere saying so. One file, two
    // generated copies, exactly like the recognition prompt.
    expect(MEAL_REVISION_SYSTEM_PROMPT).toBe(readFileSync(revisionFile, "utf8").trimEnd());
  });

  it("speaks the same taxonomy the recognition prompt does", () => {
    // The rename has to reach both or a correction re-files food the reading
    // had already filed correctly.
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("`plant_fats`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("`vegetable_oil`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("healthy_fats");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("sofrito");
    // And it still refuses the numbers the reading refuses.
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("Weight is the only number");
  });
});
