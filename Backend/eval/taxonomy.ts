import { foodGroups, portions } from "../src/contracts";

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
  juice: {
    kind: "unmapped",
    why: "Neither fruit nor necessarily sugary_drinks; the dataset has a no-added-sugar case that would be wrong in both.",
  },
  smoothie: {
    kind: "unmapped",
    why: "Between fruit, juice and dairy depending on what is in it.",
  },
  plant_milk: {
    kind: "unmapped",
    why: "Not dairy, and MEDAS has no place for it.",
  },
};

export function mapGroup(goldenGroup: string): Mapping {
  const known = table[goldenGroup];
  if (known) return known;
  if ((foodGroups as readonly string[]).includes(goldenGroup)) {
    return { kind: "exact", group: goldenGroup };
  }
  return { kind: "unmapped", why: "not in the app's FoodGroup and not in the mapping table" };
}

const sizes: Record<string, string> = { S: "small", M: "medium", L: "large" };

/**
 * `count` and `package` have no equivalent: the app has three coarse sizes and
 * no way to say "two eggs". A third of the golden items are counted, so those
 * items are scored on group only and reported separately rather than being
 * marked wrong for a distinction the schema cannot make.
 */
/**
 * Both gaps this used to report are closed.
 *
 * It existed to say what the app could not express: a counted item, because
 * there was only small/medium/large, and a packaged one, because there was no
 * label. The dish now carries `count` and a transcribed `panel`, so an
 * ingredient has only its share of one serving left to map — and that always
 * maps. What remains is the check that it was given at all.
 */
export function mapPortion(item: { portion?: string }): {
  portion: string | null;
  why?: string;
} {
  if (item.portion && sizes[item.portion]) return { portion: sizes[item.portion] };
  return { portion: null, why: `no portion on the ingredient (${item.portion ?? "none"})` };
}

export const appPortions = portions;
