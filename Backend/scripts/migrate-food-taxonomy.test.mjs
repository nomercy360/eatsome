import { describe, expect, it } from "vitest";
import { legacyFoodKind, migrateFoodJSON } from "./migrate-food-taxonomy.mjs";

describe("food taxonomy data migration", () => {
  it("uses the label to split broad legacy groups", () => {
    expect(legacyFoodKind("refined_grains", "white rice")).toBe("rice");
    expect(legacyFoodKind("refined_grains", "ramen noodles")).toBe("pasta_noodles");
    expect(legacyFoodKind("red_meat", "chashu pork")).toBe("pork");
    expect(legacyFoodKind("fish", "grilled shrimp")).toBe("shellfish");
    expect(legacyFoodKind("other", "dipping sauce")).toBe("sauce_condiment");
  });

  it("migrates nested event items and structured alternatives", () => {
    const original = {
      kind: "meal_logged",
      data: {
        items: [
          {
            group: "other",
            label: "dipping sauce",
            grams: 40,
            modelAlternatives: ["cooked_tomato_sauce"],
          },
        ],
      },
    };
    const migrated = migrateFoodJSON(original);
    expect(migrated.value.data.items[0]).toEqual({
      label: "dipping sauce",
      grams: 40,
      modelAlternatives: [{ label: "sauce or condiment", kind: "sauce_condiment" }],
      kind: "sauce_condiment",
    });
    expect(migrated.changes).toBeGreaterThan(0);
  });

  it("does not rewrite immutable raw model evidence stored as a string", () => {
    const rawModelJSON = '{"items":[{"group":"other"}]}';
    const migrated = migrateFoodJSON({ rawModelJSON, items: [{ group: "fish", label: "salmon" }] });
    expect(migrated.value.rawModelJSON).toBe(rawModelJSON);
    expect(migrated.value.items[0].kind).toBe("fish");
  });

  it("is idempotent", () => {
    const current = { items: [{ kind: "potato", label: "mashed potato", grams: 200 }] };
    expect(migrateFoodJSON(current)).toEqual({ value: current, changes: 0 });
  });
});
