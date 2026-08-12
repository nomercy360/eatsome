import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import { productionSpec } from "./spec";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v24.md");
const revisionFile = join(import.meta.dirname, "../../../prompts/revision-v4.md");

describe("meal recognition prompt", () => {
  it("matches its source and deployed version", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v24-2026-08-12");

    const wrangler = readFileSync(join(import.meta.dirname, "../../wrangler.jsonc"), "utf8");
    const deployed = /"MEAL_PROMPT_VERSION":\s*"([^"]+)"/.exec(wrangler)?.[1];
    expect(deployed).toBe(MEAL_PROMPT_VERSION);
  });

  it("asks for composition per 100 g and says so unambiguously", () => {
    // The one instruction the whole of v21 rests on. Asked for the figures for
    // the stated weight instead, the model answers just as accurately and the
    // app then multiplies a total by the weight a second time.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("per 100 g of edible portion");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("never for the weight you just reported");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`sodium_mg` in milligrams");
  });

  it("reports a published product as one row rather than rebuilding it", () => {
    // Kept because it was measured, not because it reads well. Without this
    // bullet, four runs of "subway american clubhouse footlong" came back 698,
    // 929, 698, 698 — the 929 rebuilt the sandwich from seven components. With
    // it, eight runs across two chains were all one row and all within 2 kcal.
    // It is a counterweight to our own decomposition rule, which the very next
    // bullet states.
    // v22 said to report a branded dish "exactly as you would with no brand on
    // it", which told the model to reconstruct a Subway sandwich from bread,
    // meat, cheese and sauce. Three runs of one input came back 697, 897 and
    // 665 kcal against a published 698: the reconstruction is a guess about
    // somebody else's recipe and it looks exactly as confident as the lookup.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("is ONE ingredient rather than a recipe");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Do not rebuild it from bread");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain(
      "Report the dish exactly as you would with no brand on it",
    );
  });

  it("insists on one food per label", () => {
    // 18% of the distinct labels v20 could not resolve named two foods —
    // "ham and bacon", "shredded cabbage and lettuce". A row that is two foods
    // cannot be priced as either, and no downstream step can split it.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("it must name exactly one food");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain('Never "and"');
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("report two ingredients");
  });

  it("states the Atwater check the app also runs", () => {
    // With no table to compare against, the four macronutrients agreeing with
    // the energy figure is the only self-check available. Stating it to the
    // model is cheaper than catching it afterwards.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("protein × 4 + carbohydrate × 4 + fat × 9");
  });

  it("prices food as eaten rather than as a plain ingredient", () => {
    // The salt-floor problem, fixed at its source. A composition table publishes
    // unsalted preparations, which ran 82% low on a canteen bibimbap; a model
    // asked for the food as eaten answers for the seasoning too.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("as it will actually be eaten");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("and seasoned");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("understates real food");
  });

  it("asks for one absolute ingredient weight", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("It is absolute");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Nothing multiplies it by `count`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`portion`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`size`");
  });

  it("has no taxonomy left in it", () => {
    // v21 deleted `FoodKind`. The kind guidance was about a third of v20's
    // prompt, and a stale copy of it here would be instructions for a field the
    // schema no longer emits.
    for (const retired of [
      "`kind`",
      "composition_hints",
      "`sauce_condiment`",
      "`soup_broth`",
      "other_meals_visible",
      "Mediterranean",
      "sofrito",
    ]) {
      expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain(retired);
    }
  });

  it("transcribes printed nutrition without arithmetic", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("without arithmetic");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Salt and sodium are different");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Unreadable fields are null");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Never invent missing package contents");
  });

  it("fences a person's note in the same user turn as the photo", () => {
    const image = { mimeType: "image/jpeg", imageBase64: "aGVsbG8gdGhlcmUh" };
    const prompt = productionSpec({ ...image, note: "  fried in butter  " }).userPrompt;
    expect(prompt).toContain("What the photo cannot show");
    expect(prompt).toContain('"""\nfried in butter\n"""');
    expect(productionSpec(image).userPrompt).not.toContain('"""');
  });

  it("tells the model when words are the entire input", () => {
    const typed = productionSpec({ said: "leftover lentil soup, big bowl" });
    expect(typed.userPrompt).toContain("There is no photograph");
    expect(typed.userPrompt).toContain('"""\nleftover lentil soup, big bowl\n"""');

    const captioned = productionSpec({
      mimeType: "image/jpeg",
      imageBase64: "aGVsbG8gdGhlcmUh",
      said: "2 of this at 11 am",
    });
    expect(captioned.userPrompt).toContain("closest to the camera");
    expect(captioned.userPrompt).not.toContain("There is no photograph");
  });
});

describe("meal revision prompt", () => {
  it("matches the generated revision source", () => {
    expect(MEAL_REVISION_SYSTEM_PROMPT).toBe(readFileSync(revisionFile, "utf8").trimEnd());
  });

  it("limits itself to a delta and restates the figures it moves", () => {
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("smallest possible delta");
    // The desync guard: stored figures plus editable rows can drift apart, and
    // a row renamed without new numbers looks corrected while being wrong.
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("AS IT NOW STANDS");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("looks corrected");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("`per_100g` is required");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("`kind`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("composition_hints");
  });
});
