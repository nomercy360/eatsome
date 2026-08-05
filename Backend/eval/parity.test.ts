import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { loadGoldenCases } from "./golden";
import { evalFlags, evalFoodGroups, mealStatuses } from "./schema";

/**
 * The golden's vocabulary must be sayable.
 *
 * A value the golden uses and the schema omits is a systematic zero no prompt
 * can fix: every model fails those cases identically and the report reads as a
 * model problem. `filling_unknown` was exactly that — in the labels, absent from
 * the schema and the prompt, so a wrap with a hidden filling could only be
 * guessed at or dropped.
 */
const prompt = readFileSync(join(import.meta.dirname, "../../prompts/meal-v6.md"), "utf8");
const cases = loadGoldenCases();

describe("golden and schema speak the same language", () => {
  it("every group in the golden exists in the schema", () => {
    const used = new Set(cases.flatMap((one) => one.golden.map((item) => item.group)));
    expect([...used].filter((g) => !(evalFoodGroups as readonly string[]).includes(g))).toEqual([]);
  });

  it("every flag in the golden exists in the schema and the prompt", () => {
    const used = new Set(cases.flatMap((one) => one.golden.flatMap((item) => item.flags ?? [])));
    expect([...used].filter((f) => !(evalFlags as readonly string[]).includes(f))).toEqual([]);
    expect([...used].filter((f) => !prompt.includes(f))).toEqual([]);
  });

  it("every meal_status in the golden exists in the schema and the prompt", () => {
    const used = new Set(cases.map((one) => one.meal_status).filter(Boolean) as string[]);
    expect([...used].filter((s) => !(mealStatuses as readonly string[]).includes(s))).toEqual([]);
    expect([...used].filter((s) => !prompt.includes(s))).toEqual([]);
  });
});
