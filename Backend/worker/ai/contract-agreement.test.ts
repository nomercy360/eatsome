import { describe, expect, it } from "vitest";
import { compositionSchema, panelBases } from "../../src/contracts";
import { MEAL_RECOGNITION_SYSTEM_PROMPT } from "./prompt.generated";

/**
 * The prompt and the schema are one contract written twice, and nothing checked
 * that the two copies said the same thing.
 *
 * This exists because they diverged and every test still passed. `prompt.test.ts`
 * asserted the prompt contains "set `basis` to `estimated_serving`";
 * `recognize.test.ts` asserted the Gemini schema does not offer that value. Both
 * green, in the same suite, about the same field — and a coffee logged against
 * that pair would have been described by the prompt and then rejected by the
 * validator.
 *
 * It is the same failure as v16, which shipped a weighing prompt against a
 * schema that emitted no weights, with the polarity reversed: there the schema
 * was silent about what the prompt asked for, here the schema refuses it.
 * Testing each half against its own expectations cannot catch either, because
 * each half is individually correct. Only a test that reads both can.
 *
 * The rule these all share: **a value the prompt names must be a value the
 * schema accepts, and a field the schema requires must be a field the prompt
 * asks for.** Everything below is that rule applied to one part of the contract.
 */
describe("The prompt and the schema describe the same contract", () => {
  /** Prose, lowercased, so a match is about content rather than capitalisation. */
  const prompt = MEAL_RECOGNITION_SYSTEM_PROMPT.toLowerCase();

  /** Every `` `backticked` `` token the prompt names. The prompt's own
   *  convention for "this is a literal value or field name", which makes it
   *  possible to ask what the prompt claims without parsing English. */
  const quoted = new Set(
    Array.from(MEAL_RECOGNITION_SYSTEM_PROMPT.matchAll(/`([^`\n]+)`/g), (m) => m[1]),
  );

  describe("panel bases", () => {
    it("names no basis the schema would reject", () => {
      // The one that actually broke. A basis in the prompt and not in the enum
      // is an instruction to produce output the validator throws away.
      const named = [...quoted].filter((token) => /^(per_|estimated_)/.test(token));
      const strays = named.filter((token) => !(panelBases as readonly string[]).includes(token));
      expect(strays, `prompt names basis values the schema rejects: ${strays.join(", ")}`).toEqual(
        [],
      );
    });

    it("names every basis the schema accepts", () => {
      // The other direction: a value the model is never told about is a value
      // it will not use, which makes the enum a lie about what can come back.
      const missing = panelBases.filter((basis) => !quoted.has(basis));
      expect(missing, `schema accepts bases the prompt never names: ${missing.join(", ")}`).toEqual(
        [],
      );
    });
  });

  describe("composition", () => {
    const keys = Object.keys(compositionSchema.shape);

    it("asks for every figure the schema requires", () => {
      // `per_100g` is required on every ingredient, every alternative and every
      // size. A figure the schema demands and the prompt never mentions fails
      // *every* recognition, not an unusual one.
      const missing = keys.filter((key) => !quoted.has(key));
      expect(
        missing,
        `schema requires figures the prompt never asks for: ${missing.join(", ")}`,
      ).toEqual([]);
    });

    it("states the count of figures correctly, or does not state one", () => {
      // The prompt used to end that list with "All five, always". Left behind
      // after a column is added, a stated count is worse than no count: it is
      // an explicit instruction to omit the new field.
      const words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"];
      const claimed = words.findIndex((word) => prompt.includes(`all ${word}, always`));
      if (claimed >= 0) {
        expect(
          claimed + 1,
          `prompt says "all ${words[claimed]}, always" but per_100g has ${keys.length} fields`,
        ).toBe(keys.length);
      }
    });

    it("includes ethanol in the energy check it states", () => {
      // The prompt states the Atwater identity so the model can self-check. With
      // an alcohol column and no ethanol term, the prompt would be instructing
      // the model to fail its own check on every drink.
      const statesCheck = prompt.includes("× 4") || prompt.includes("x 4");
      if (statesCheck) {
        expect(
          prompt.includes("× 7") || prompt.includes("x 7"),
          "prompt states the Atwater check without the ethanol term",
        ).toBe(true);
      }
    });
  });
});
