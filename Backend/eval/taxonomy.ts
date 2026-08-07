import { foodGroups } from "../src/contracts";

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
 *   unmapped   — no home in `FoodGroup` at all. These items cannot be scored,
 *                and every trap that depends on them is unmeasurable until the
 *                taxonomy changes. `pnpm eval:coverage` counts them.
 */
export type Mapping =
  | { kind: "exact"; group: string }
  | { kind: "renamed"; group: string }
  | { kind: "lossy"; group: string; why: string }
  | { kind: "unmapped"; why: string };

const table: Record<string, Mapping> = {
  refined_grain: { kind: "renamed", group: "refined_grains" },
  whole_grain: { kind: "renamed", group: "whole_grains" },
  butter_margarine_cream: { kind: "renamed", group: "butter" },

  potatoes: {
    kind: "unmapped",
    why: "Not vegetables in MEDAS terms — counting them there would credit an item 3 serving for chips. Needs its own group or an explicit decision to score them nowhere.",
  },
  sauce: {
    kind: "unmapped",
    why: "The prompt deliberately routes sauces to what they are made of — mayonnaise to butter, oil dressings to olive_oil, tomato to sofrito, yoghurt to dairy. The dataset keeps `sauce` as a category, so these items disagree by design rather than by error.",
  },
};
// `juice`, `smoothie` and `plant_milk` were unmapped here until the app grew
// groups for them, and `coffee` and `tea` never reached this table because the
// golden set has no drink-only meal — they fell through to `other`, which is
// how a black coffee came to be worth 2 g of protein. All five now resolve
// through `foodGroups` as exact matches.

export function mapGroup(goldenGroup: string): Mapping {
  const known = table[goldenGroup];
  if (known) return known;
  if ((foodGroups as readonly string[]).includes(goldenGroup)) {
    return { kind: "exact", group: goldenGroup };
  }
  return { kind: "unmapped", why: "not in the app's FoodGroup and not in the mapping table" };
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
