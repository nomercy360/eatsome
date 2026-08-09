import { readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";

/**
 * The dataset's own schema, kept as it was written rather than reshaped to fit
 * the app. Where the two disagree, `taxonomy.ts` says so out loud — a golden set
 * bent to match the code cannot tell you the code is wrong.
 *
 * The one deliberate reshaping is quantity. The set was annotated on the
 * `count × size × portion` ladder the app used before August 2026; the app now
 * asks for absolute grams and nothing else, and a golden that keeps answering
 * in ladder cannot grade the number the app actually scores — a systematic
 * ×0.68 under-read sits comfortably inside half-a-serving tolerance. So
 * quantity was re-annotated in grams, and `weight_source` says how each number
 * was arrived at, because a converted ladder value looking exactly like a
 * weighed one is the same trap at a smaller scale.
 *
 * `protein_g` was removed in the same pass rather than left empty. It was an
 * annotator's rough figure written per serving under the ladder, and once the
 * weights moved it no longer corresponded to its own `weight_g` — 14 of 36 came
 * to imply an impossible density, chicken schnitzel at 3.4 g per 100 g. A field
 * that looks like ground truth and is not is worse than an absent one, which is
 * the argument that retired the ladder in the first place. Protein is graded
 * against `eval/labelled.json`, where the figure was printed on a board or a
 * package: `pnpm eval:nutrients`.
 */
export type GoldenItem = {
  name: string;
  group: string;
  alternatives?: string[];
  /**
   * Edible weight on the plate, absolute: everything of this ingredient that
   * is present, across every serving in the photograph — the same definition
   * the prompt gives the model, so the two numbers are directly comparable.
   */
  weight_g: number;
  /**
   * Where `weight_g` came from, in descending order of trust:
   *
   *   label     — printed on the package (net weight, panel basis). A
   *               measurement; graded tight.
   *   annotated — estimated from the photograph by the annotator, against
   *               references in frame. An honest estimate; graded with the
   *               tolerance an estimate deserves.
   *   ladder    — mechanically derived from the retired count×size×portion
   *               annotation. Scaffolding awaiting a human pass; graded at the
   *               half-serving resolution the ladder actually had.
   *
   * The text track (`golden-text/`) grades words instead of pixels, and its
   * provenance tiers mirror how much the words actually say — the same ranking
   * prompt v18 gives the model:
   *
   *   stated    — the description states the figure ("7 g creatine"). A fact to
   *               transcribe; graded tight, because rounding a stated number is
   *               the failure this tier exists to catch.
   *   counted   — a count of a named thing ("3 french toasts", "two eggs").
   *               Count × a canonical unit weight; graded at the spread real
   *               units have.
   *   typical   — a vessel or size word ("big bowl"). The weakest evidence
   *               there is, graded as a range: any plausible serving passes,
   *               and the case is really asking whether the size word moved
   *               the number at all.
   */
  weight_source: "label" | "annotated" | "ladder" | "stated" | "counted" | "typical";
  /**
   * Overrides the source-based tolerance where the default misfits — a spoon
   * of sugar is `counted` but the count floor would swallow the whole figure.
   */
  weight_tolerance_g?: number;
  flags?: string[];
  /** Not visible in the photo: reachable only through the note or a recipe. */
  hidden?: boolean;
};

/** Figures a label prints, and what a correct answer transcribes. */
export type GoldenPanel = {
  protein?: number | null;
  calories?: number | null;
  fat?: number | null;
  carbohydrate?: number | null;
  sodium?: number | null;
  caffeine?: number | null;
};

/**
 * One named thing on the tray.
 *
 * The boundary is what is physically served together: butter in its own wrapper
 * is a dish, butter spread on the bread is an ingredient of it. Mixed into one
 * vessel collapses — a rice bowl is one dish, not rice plus topping plus egg —
 * while discrete countable units of a kind stay separate even when they share a
 * container, which is why a box of sushi is several dishes and a burrito bowl
 * is one.
 */
export type GoldenDish = {
  name: string;
  /**
   * Servings of this dish present. Three slices of bread is count 3. A label,
   * never a factor: each ingredient's `weight_g` already covers all of them.
   */
  count: number;
  panel?: GoldenPanel | null;
  /**
   * Expected milligrams, derived from the drink and its count — never asked of
   * a model, which cannot see caffeine. Null where the photograph genuinely
   * cannot settle it: barley tea and oolong are the same amber in a tumbler.
   */
  caffeine_mg?: number | null;
  caffeine_note?: string;
  ingredients: GoldenItem[];
};

export type GoldenCase = {
  id: string;
  photo: string;
  scene?: string;
  meal_status?: string;
  /**
   * Retired by dishes, kept so old files still load. It existed because a flat
   * list could not tell two vegetable rows inside one bowl from two plates of
   * vegetables; the structure now says which it is.
   */
  dedup_note?: string;
  traps: string[];
  dishes: GoldenDish[];
  /**
   * A line the person typed, sent on EVERY track, permanently part of the input.
   *
   * Never the hidden-item note: that one belongs to `--notes`, is generated from
   * the `hidden` flags, and putting it here would hand a plain run the answer
   * the case exists to withhold. IMG_3152 carried exactly that and was only
   * harmless because nothing read this field. This is for cases whose correct
   * answer is undefined without the line:
   * a dinner-party table is either one share or six dishes depending on whether
   * the person said the rest is theirs, and the prompt's nearest-setting rule
   * makes the second reading reachable only through this line. The golden then
   * encodes what is in the photograph under that line — the whole table, at the
   * sizes it is actually served in — not the portion the person ate.
   */
  user_note?: string;
  /** Held back from prompt iteration; see eval/README.md. */
  holdout?: boolean;
};

const evalRoot = import.meta.dirname;

export function loadGoldenCases(): GoldenCase[] {
  const dir = join(evalRoot, "golden");
  const photos = readdirSync(join(evalRoot, "photos"));
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const id = basename(name, ".json");
      const raw = JSON.parse(readFileSync(join(dir, name), "utf8")) as Omit<
        GoldenCase,
        "id" | "photo"
      >;
      // The dataset stores `photos/IMG_1234.jpeg`; `photoPath` adds the
      // directory itself, so the prefix is stripped rather than doubled.
      const declared = (raw as { photo?: string }).photo?.replace(/^photos\//, "");
      const found = photos.find((file) => file.slice(0, file.lastIndexOf(".")) === id);
      return {
        ...raw,
        traps: raw.traps ?? [],
        dishes: raw.dishes ?? [],
        id,
        photo: declared ?? found ?? `${id}.JPG`,
      };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
}

/** Every ingredient with the dish it came from, for group-level scoring. */
export function goldenIngredients(
  dishes: GoldenDish[],
): Array<GoldenItem & { dish: string; dishCount: number }> {
  return dishes.flatMap((dish) =>
    dish.ingredients.map((item) => ({
      ...item,
      dish: dish.name,
      dishCount: dish.count,
    })),
  );
}
