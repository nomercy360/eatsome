import { foodKinds } from "../src/contracts";

/**
 * The golden set speaks a richer vocabulary than the app does, and the gap has
 * to be visible rather than scored as if it were model error.
 *
 * The dataset was written from real meals, so where it disagrees with the app's
 * taxonomy it is usually the dataset that is right about the food and the app
 * that has a decision to make. Three kinds of disagreement:
 *
 *   renamed    — the same idea, a different string. Mapped silently.
 *   lossy      — mapped, but something is lost. Reported.
 *   unmapped   — no home in `FoodKind` at all. These items cannot be scored,
 *                and every trap that depends on them is unmeasurable until the
 *                taxonomy changes. `pnpm eval:coverage` counts them.
 */
export type Mapping =
  | { kind: "exact"; group: string }
  | { kind: "renamed"; group: string }
  | { kind: "lossy"; group: string; why: string }
  | { kind: "unmapped"; why: string };

const table: Record<string, Mapping> = {
  refined_grain: {
    kind: "lossy",
    group: "bread_flatbread",
    why: "The old annotation does not say rice, pasta, bread, or cereal; map by food name before scoring.",
  },
  whole_grain: {
    kind: "lossy",
    group: "bread_flatbread",
    why: "Whole grain is now a composition hint; the food still needs a rice/pasta/bread/cereal kind.",
  },
  white_meat: { kind: "renamed", group: "poultry" },
  red_meat: {
    kind: "lossy",
    group: "beef",
    why: "The old annotation does not distinguish beef, pork, or lamb/game.",
  },
  processed_meat: { kind: "exact", group: "processed_meat" },
  fish: { kind: "lossy", group: "fish", why: "The old annotation combines finfish and shellfish." },
  egg: { kind: "exact", group: "egg" },
  dairy: {
    kind: "lossy",
    group: "milk",
    why: "The old annotation combines milk, yogurt, cheese, and cream.",
  },
  legumes: {
    kind: "lossy",
    group: "legume",
    why: "The old annotation combines legumes and soy products.",
  },
  vegetables: {
    kind: "lossy",
    group: "vegetable",
    why: "The old annotation combines vegetables, mushrooms, and seaweed.",
  },
  fruit: { kind: "exact", group: "fruit" },
  nuts: { kind: "renamed", group: "nuts_seeds" },
  sweets: {
    kind: "lossy",
    group: "chocolate_candy",
    why: "The old annotation combines sugar, candy, cake, and frozen desserts.",
  },
  pastry: { kind: "exact", group: "pastry" },
  olive_oil: { kind: "renamed", group: "oil" },
  sofrito: { kind: "renamed", group: "sauce_condiment" },
  sugary_drinks: { kind: "renamed", group: "soft_sports_energy_drink" },
  butter_margarine_cream: {
    kind: "lossy",
    group: "butter_margarine",
    why: "Cream is now a distinct food kind.",
  },
  healthy_fats: { kind: "renamed", group: "avocado_olive" },
  potatoes: { kind: "renamed", group: "potato" },
  sauce: { kind: "renamed", group: "sauce_condiment" },
  alcohol: {
    kind: "lossy",
    group: "beer",
    why: "The old annotation combines beer, wine, spirits, and cocktails.",
  },
  other: { kind: "renamed", group: "unknown" },
};
// `juice`, `smoothie` and `plant_milk` were unmapped here until the app grew
// groups for them, and `coffee` and `tea` never reached this table because the
// golden set has no drink-only meal — they fell through to `other`, which is
// how a black coffee came to be worth 2 g of protein. All five now resolve
// through `foodKinds` as exact matches.

export function mapGroup(goldenGroup: string): Mapping {
  const known = table[goldenGroup];
  if (known) return known;
  if ((foodKinds as readonly string[]).includes(goldenGroup)) {
    return { kind: "exact", group: goldenGroup };
  }
  return { kind: "unmapped", why: "not in the app's FoodKind and not in the mapping table" };
}

/**
 * Quantity no longer maps — it converts. The golden and the app both speak
 * absolute grams from v5/v17, so the only check left is that a weight was
 * annotated at all, and where it came from. A `ladder`-sourced weight is
 * scaffolding derived from the retired count×size×portion annotation; coverage
 * reports it so the hand pass has a worklist rather than a claim of done.
 */
export function weightProvenance(item: { weight_g?: number; weight_source?: string }): {
  weighed: boolean;
  source: string;
} {
  if (item.weight_g == null) return { weighed: false, source: "missing" };
  return { weighed: true, source: item.weight_source ?? "unstated" };
}
