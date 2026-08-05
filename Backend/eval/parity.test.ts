import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { loadGoldenCases } from "./golden";
import { evalFlags, evalFoodGroups, mealStatuses } from "./schema";
import { EVAL_PROMPT_FILE } from "./version";

/**
 * The golden's vocabulary must be sayable.
 *
 * A value the golden uses and the schema omits is a systematic zero no prompt
 * can fix: every model fails those cases identically and the report reads as a
 * model problem. `filling_unknown` was exactly that — in the labels, absent from
 * the schema and the prompt, so a wrap with a hidden filling could only be
 * guessed at or dropped.
 */
// The filename comes from `version.ts` rather than being written out again:
// this test sat on `meal-v6.md` while the harness had already moved, which
// means it was checking the flags of a prompt nobody was running.
const prompt = readFileSync(join(import.meta.dirname, "../../prompts", EVAL_PROMPT_FILE), "utf8");
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

  /**
   * The other direction, which the three tests above did not cover.
   *
   * A group the PROMPT names and the schema omits is the same systematic zero,
   * arriving from the opposite side: `alternatives` is a strict enum, so a model
   * obeying the instruction cannot emit the value at all. `meal-v7` told models
   * to put `butter` in `alternatives` — the app's spelling of
   * `butter_margarine_cream`, and not a member of `evalFoodGroups`. The
   * instruction was unfollowable for as long as it stood, and nothing failed.
   */
  it("every food group the prompt names exists in the schema", () => {
    const named = new Set([...prompt.matchAll(/`([a-z][a-z_]{2,})`/g)].map((m) => m[1]));
    const groupish = [...named].filter(
      (word) =>
        // Only words that look like a group claim: present in the app's
        // vocabulary, or a near-miss of a schema group. Field names, flags and
        // measures are checked by the tests above and are not groups.
        !(evalFoodGroups as readonly string[]).includes(word) &&
        !(evalFlags as readonly string[]).includes(word) &&
        !(mealStatuses as readonly string[]).includes(word) &&
        ![
          "count",
          "size",
          "package",
          "group",
          "alternatives",
          "notes",
          "name",
          "flags",
          "meal_status",
          "other_meals_visible",
          "whole_grains",
          "refined_grains",
        ].includes(word) &&
        (evalFoodGroups as readonly string[]).some(
          (g) => g.startsWith(word) || g.endsWith(word) || word.startsWith(g),
        ),
    );
    expect(groupish).toEqual([]);
  });

  it("every meal_status in the golden exists in the schema and the prompt", () => {
    const used = new Set(cases.map((one) => one.meal_status).filter(Boolean) as string[]);
    expect([...used].filter((s) => !(mealStatuses as readonly string[]).includes(s))).toEqual([]);
    expect([...used].filter((s) => !prompt.includes(s))).toEqual([]);
  });
});
