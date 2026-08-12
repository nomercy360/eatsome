import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt";
import { MEAL_REVISION_SYSTEM_PROMPT } from "./revision.generated";
import { productionSpec } from "./spec";

const promptFile = join(import.meta.dirname, "../../../prompts/meal-v20.md");
const revisionFile = join(import.meta.dirname, "../../../prompts/revision-v3.md");

describe("meal recognition prompt", () => {
  it("matches its source and deployed version", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toBe(readFileSync(promptFile, "utf8").trimEnd());
    expect(MEAL_PROMPT_VERSION).toBe("meal-v20-2026-08-12");

    const wrangler = readFileSync(join(import.meta.dirname, "../../wrangler.jsonc"), "utf8");
    const deployed = /"MEAL_PROMPT_VERSION":\s*"([^"]+)"/.exec(wrangler)?.[1];
    expect(deployed).toBe(MEAL_PROMPT_VERSION);
  });

  it("keeps identity, preparation, and composition separate", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      "Food identity, preparation, and nutrient composition are separate",
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`preparation` contains only methods");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`composition_hints`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`whole_grain`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("`soy_based`");
  });

  it("uses a food taxonomy instead of the retired diet taxonomy", () => {
    for (const kind of [
      "`potato`",
      "`beef`",
      "`rice`",
      "`mayonnaise_dressing`",
      "`sauce_condiment`",
      "`soup_broth`",
    ]) {
      expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(kind);
    }
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Potato is never `vegetable`");

    for (const retired of ["Mediterranean", "MEDAS", "adherence", "olive_oil", "sofrito"]) {
      expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain(retired);
    }
  });

  it("classifies an unnamed dip honestly without dropping it", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain(
      'A generic dipping sauce remains `sauce_condiment` with label "dipping sauce"',
    );
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Do not guess its recipe");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("not `unknown`");
  });

  it("asks for one absolute ingredient weight and no nutrient guesses", () => {
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("It is absolute");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Nothing multiplies it by `count`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`portion`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).not.toContain("`size`");
    expect(MEAL_RECOGNITION_SYSTEM_PROMPT).toContain("Never report calories or macros from memory");
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

  it("uses the same taxonomy and limits itself to a delta", () => {
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("smallest possible delta");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("`kind` is a nutrition-oriented identity");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("generic dipping sauce is `sauce_condiment`");
    expect(MEAL_REVISION_SYSTEM_PROMPT).toContain("Weight is the only numeric estimate");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("olive_oil");
    expect(MEAL_REVISION_SYSTEM_PROMPT).not.toContain("sofrito");
  });
});
