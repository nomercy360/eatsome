import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import { recognitionSpec } from "./spec";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v28.md");
const revisionFile = join(import.meta.dirname, "../../../prompts/revision-v6.md");

describe("meal recognition prompt", () => {
  it("matches its source, and has only one place to say which version it is", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v28-2026-08-16");

    // It used to be a wrangler var *as well* as the generated constant, and
    // the recognition cache keys on it — so a deploy that bumped one and not
    // the other would either replay the old prompt's answers under the new
    // prompt's name or throw away a whole cache for nothing. The generated
    // constant won because it is the one that cannot disagree with the prompt
    // text beside it.
    const wrangler = readFileSync(join(import.meta.dirname, "../../wrangler.jsonc"), "utf8");
    expect(wrangler).not.toContain("MEAL_PROMPT_VERSION");
  });

  it("asks for composition per 100 g and says so unambiguously", () => {
    // The one instruction the whole of v21 rests on. Asked for the figures for
    // the stated weight instead, the model answers just as accurately and the
    // app then multiplies a total by the weight a second time.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("per 100 g of edible portion");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("never for the weight you just reported");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`sodium_mg` and `caffeine_mg` in milligrams");
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

  it("asks how a branded row is sold, because that decides how it is corrected", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("nobody eats 217 g of Big Mac");
    // A size is a different product. v17 deleted a size control that was a
    // vague multiplier and moved no number; this one carries its own figures.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "A size is a different product, never a multiplier",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Never invent a ladder");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "Treat every branded ingredient independently",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "Never stop after grounding the first branded dish",
    );
  });

  it("asks for open choices as priced forks, and for what decided the default", () => {
    // v28. `sizes` could say Regular/Footlong and nothing else; on the same
    // inputs the model put the drink in an opaque cup (Coke/Diet Coke/Sprite,
    // Δ220 kcal) and the milk in a latte in this shape (`eval/forks-poc.md`).
    // `chosen_from` is the gate: prompted not to fork on a settled input, the
    // model still offered sizes on "grande oat milk latte" three runs in four;
    // asked to say what decided the default, it was right 16 of 16.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Open choices — `forks`:");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Exactly one option per fork is `chosen`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "Only an `assumed` fork will be put to the person",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("in the market's own language");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Empty is the normal case");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`sizes`");
  });

  it("insists on one food per label", () => {
    // 18% of the distinct labels v20 could not resolve named two foods —
    // "ham and bacon", "shredded cabbage and lettuce". A row that is two foods
    // cannot be priced as either, and no downstream step can split it.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("it must name exactly one food");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain('Never "and"');
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("report two ingredients");
  });

  it("states the Atwater check the app also runs, ethanol included", () => {
    // With no table to compare against, the macronutrients agreeing with the
    // energy figure is the only self-check available. Stating it to the model
    // is cheaper than catching it afterwards. Ethanol at 7 is what stopped it
    // firing on every beer.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "protein × 4 + carbohydrate × 4 + fat × 9 + alcohol × 7",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`kcal` includes the energy of that ethanol");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain(
      "protein × 4 + carbohydrate × 4 + fat × 9 + alcohol × 7",
    );
  });

  it("asks for all seven composition figures, and says zero is an answer", () => {
    // Five was the number for four versions. The schema now requires seven and
    // a prompt still saying five would have every answer fail validation —
    // which is what happened for the hour between the schema and this file.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("All seven, always");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("All five");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`sodium_mg` and `caffeine_mg` in milligrams");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`alcohol` is grams of ethanol per 100 g");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "`caffeine_mg` is composition, exactly as `sodium_mg` is",
    );
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("All seven, always");
  });

  it("says an empty answer is a real answer", () => {
    // The couldn't-read signal is no dishes. Without this line the model
    // assembles a meal out of a greeting rather than declining, and a meal
    // nobody ate is worse than a screen saying it did not understand.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("return no dishes");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("An empty answer is a real answer");
  });

  it("has nothing to say about activities, because none reach it", () => {
    // Activities are not in the MVP, and the path that would have carried one
    // to the model is gone. A stale instruction here would be asking for a
    // field neither provider's schema declares — the v16 failure, again.
    for (const gone of ["activit", "`entry`", "duration_minutes", "start_time", "sauna"]) {
      expect(MEAL_RECOGNITION_SYSTEM_PROMPT.toLowerCase()).not.toContain(gone.toLowerCase());
    }
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
    // v25 let an unlabelled coffee carry a caffeine *estimate* on the panel
    // under `estimated_serving`. Caffeine is composition now, the basis is gone
    // from `panelBases`, and a prompt still asking for it would fail every
    // coffee at validation. This assertion is the polarity the schema has.
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("estimated_serving");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("It is transcription and nothing else");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("an ABV percentage is not this field");
  });

  it("fences a person's note in the same user turn as the photo", () => {
    const image = { mimeType: "image/jpeg", imageBase64: "aGVsbG8gdGhlcmUh" };
    const prompt = recognitionSpec({ ...image, note: "  fried in butter  " }).userPrompt;
    expect(prompt).toContain("What the photo cannot show");
    expect(prompt).toContain('"""\nfried in butter\n"""');
    expect(recognitionSpec(image).userPrompt).not.toContain('"""');
  });

  it("tells the model when words are the entire input", () => {
    const typed = recognitionSpec({ said: "leftover lentil soup, big bowl" });
    expect(typed.userPrompt).toContain("There is no photograph");
    expect(typed.userPrompt).toContain('"""\nleftover lentil soup, big bowl\n"""');

    const captioned = recognitionSpec({
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
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("four of these");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("`dish_counts`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("`kind`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("composition_hints");
  });
});
