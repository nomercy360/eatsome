import { describe, expect, it } from "vitest";
import { loadTextCases } from "./golden-text";
import { evalFoodGroups } from "./schema";

/**
 * The dataset is data, and data drifts: a typo'd group would silently score as
 * a permanent miss, and a case whose forbidden list contradicts its own golden
 * would fail every honest answer. Validated here so a bad case fails loudly at
 * commit time instead of quietly costing a model its pass rate.
 */
describe("text-track dataset", () => {
  const cases = loadTextCases();
  const groups = new Set<string>(evalFoodGroups);

  it("loads every case with a non-empty description and at least one dish", () => {
    expect(cases.length).toBeGreaterThanOrEqual(14);
    for (const one of cases) {
      expect(one.said.trim().length, one.id).toBeGreaterThan(0);
      expect(one.dishes.length, one.id).toBeGreaterThan(0);
    }
  });

  it("uses only groups the eval schema can express", () => {
    for (const one of cases) {
      for (const dish of one.dishes) {
        for (const item of dish.ingredients) {
          expect(groups.has(item.group), `${one.id}: ${item.group}`).toBe(true);
          for (const alt of item.alternatives ?? []) {
            expect(groups.has(alt), `${one.id}: ${alt}`).toBe(true);
          }
        }
      }
      for (const group of one.forbidden_groups ?? []) {
        expect(groups.has(group), `${one.id}: forbidden ${group}`).toBe(true);
      }
      for (const fork of one.expected_forks ?? []) {
        expect(fork.length, `${one.id}: a fork needs at least two rivals`).toBeGreaterThan(1);
        for (const group of fork) expect(groups.has(group), `${one.id}: ${group}`).toBe(true);
      }
    }
  });

  it("grades every weight on a text tier, and text tiers only", () => {
    // A photo tier here would claim someone read a photograph that does not
    // exist; the provenance is the words, and the tier must say which kind.
    for (const one of cases) {
      for (const dish of one.dishes) {
        for (const item of dish.ingredients) {
          expect(
            ["stated", "counted", "typical"],
            `${one.id}: ${item.name} graded as ${item.weight_source}`,
          ).toContain(item.weight_source);
          expect(item.weight_g, `${one.id}: ${item.name}`).toBeGreaterThan(0);
        }
      }
    }
  });

  it("never forbids a group its own golden expects", () => {
    for (const one of cases) {
      const expected = new Set(
        one.dishes.flatMap((dish) =>
          dish.ingredients.flatMap((item) => [item.group, ...(item.alternatives ?? [])]),
        ),
      );
      for (const group of one.forbidden_groups ?? []) {
        expect(expected.has(group), `${one.id}: ${group} both expected and forbidden`).toBe(false);
      }
    }
  });

  it("declares every expected fork on an item the golden actually carries", () => {
    // A fork the golden cannot express is unpassable: the check wants an item
    // whose group is one rival with another as its alternative, so the golden
    // itself must hold that item or the case fails every model forever.
    for (const one of cases) {
      const items = one.dishes.flatMap((dish) => dish.ingredients);
      for (const fork of one.expected_forks ?? []) {
        const carried = items.some(
          (item) =>
            fork.includes(item.group) &&
            (item.alternatives ?? []).some((alt) => fork.includes(alt) && alt !== item.group),
        );
        expect(carried, `${one.id}: fork ${fork.join(" vs ")} not in the golden`).toBe(true);
      }
    }
  });

  it("keeps stated figures exact enough to catch rounding", () => {
    // The stated tier exists to catch 13 becoming 15. A stated item with a
    // hand-widened tolerance above the tier default has quietly stopped
    // testing transcription.
    for (const one of cases) {
      for (const dish of one.dishes) {
        for (const item of dish.ingredients) {
          if (item.weight_source !== "stated") continue;
          const cap = Math.max(2, item.weight_g * 0.1);
          expect(
            item.weight_tolerance_g ?? cap,
            `${one.id}: ${item.name} stated but graded loose`,
          ).toBeLessThanOrEqual(cap);
        }
      }
    }
  });

  it("holds three cases back from iteration", () => {
    expect(cases.filter((one) => one.holdout).map((one) => one.id)).toEqual([
      "TXT_101",
      "TXT_102",
      "TXT_103",
    ]);
  });
});
