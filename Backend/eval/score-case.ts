import { type GoldenCase, goldenIngredients } from "./golden";
import { evalRecognitionSchema } from "./schema";

/**
 * One answer against one golden case, in the dataset's own vocabulary.
 *
 * There is no mapping layer any more and no excluded items: the models are asked
 * for `potatoes` and counted eggs, so failing to produce them is a real failure
 * rather than a schema artefact. The app's narrower taxonomy is the thing that
 * has to catch up, and these runs are what tells it what to catch up to.
 *
 * Deterministic throughout. The output is a closed enum plus a count or a size —
 * exact answers, so a model-graded assertion would add cost, latency and
 * nondeterminism to a question that has one.
 */
export type CaseScore = {
  parsed: boolean;
  parseError?: string;
  recall: number;
  precision: number;
  /** Of the groups found, how many also got the ingredient portion right. */
  portionMatch: number;
  /** Dishes whose count was exactly right, over dishes the golden counts above one. */
  countMatch: number;
  countTotal: number;
  /** How many dishes were reported, against how many the golden names. */
  dishCount: number;
  dishExpected: number;
  /**
   * Golden dishes with a counterpart in the answer, matched on the set of food
   * groups inside rather than on the name — "som tam" and "green papaya salad"
   * are the same dish and no string comparison knows that.
   */
  structureMatch: number;
  /** Figures printed on a label and transcribed wrongly, or invented. */
  panelWrong: string[];
  /** Milligrams the drinks imply, against what the golden expects. */
  caffeineExpected: number | null;
  caffeineActual: number | null;
  missedGroups: string[];
  spuriousGroups: string[];
  duplicateGroups: string[];
  mealStatusOk: boolean | null;
  otherMealsOk: boolean | null;
  /** Items the golden marks invisible. Excluded from a plain photo run, which
   *  cannot see them, and required on a note run, which was told about them. */
  hiddenMissed: string[];
  /** Why the case failed, in the order the checks run. Empty means it passed. */
  failures: string[];
  pass: boolean;
};

const RECALL_FLOOR = 0.8;
/**
 * Two thirds of the tray grouped the way it is served. Lower and a rice bowl
 * split into four dishes would pass, which is the failure the rewrite exists to
 * catch; higher and one debatable boundary — is the butter its own dish? —
 * fails an answer that read the food correctly.
 */
const STRUCTURE_FLOOR = 0.67;

/**
 * The measuring instrument is versioned like everything else it measures.
 *
 * Gemini went 21/28 to 17/28 to 21/28 across this session without answering a
 * single photo differently — the ruler changed. Numbers from two scorer versions
 * are no more comparable than numbers from two prompts, and in a month nothing
 * in a report would say which ruler produced it. Bump this whenever a gate, a
 * denominator or a definition moves.
 *
 * v1  recall only; duplicates, counts and meal_status computed and discarded
 * v2  everything gated, which failed models for matching a golden that repeats
 *     groups, and gated meal_status where the label itself is unsettled
 * v3  gates are recall and, on a note run, the items the note named; excess is
 *     measured against the golden's own repeats; counted items need the number
 * v4  the golden's own `alternatives` count as right answers. They were
 *     declared on 16 items across 13 cases and read by nothing, so a case that
 *     admitted an ambiguity still scored the admitted reading as an error. They
 *     no longer count as spurious either, for the same reason.
 * v5  dishes. Groups are still the core, but a tray of four things reported as
 *     one dish is now a failure the old scorer could not see, and a rice bowl
 *     reported as four dishes likewise. Structure is matched on the groups
 *     inside a dish, never on its name. Counts move from the item to the dish.
 *     Duplicate-group gating retires: the structure says whether two vegetable
 *     rows are one bowl or two plates, which is what it was standing in for.
 *     Adds the two checks a transcribed label needs — a wrong figure, and a
 *     figure invented where the golden says nothing is legible.
 */
/**
 * v6  dish matching uses overlap rather than Jaccard, and honours the golden's
 *     alternatives. Two cases scored 0% structure with one dish expected and
 *     one answered: a bubble waffle decomposed into three groups shared
 *     everything the golden had, and escargot answered as its own declared
 *     alternative counted as a different dish. Both were the ruler, not the
 *     model.
 */
export const SCORER_VERSION = "scorer-v6-2026-08-06";

/**
 * Milligrams per serving, for deriving what a drink implies.
 *
 * Never asked of a model: caffeine is not visible, and a figure estimated from
 * a photograph of a cup is a guess wearing a unit. The model says which drink
 * and how many; this table says the rest, and the golden asserts the product.
 */
export const CAFFEINE_MG_PER_SERVING: Record<string, number> = {
  coffee: 95,
  tea: 45,
  sugary_drinks: 0,
};

/**
 * `told` says the run sent the hidden-item note. It changes what counts: told
 * about the butter, a model that omits it has failed, and a model that finds it
 * without being told was guessing.
 *
 * It is deliberately not "the run sent any text". A case can carry a user line
 * of its own — "everything on this table is mine" — which says nothing about
 * invisible ingredients, and treating that as having been told would gate
 * hidden items the model was never given.
 */
export function scoreCase(golden: GoldenCase, raw: string, told = false): CaseScore {
  const empty: CaseScore = {
    parsed: false,
    recall: 0,
    precision: 0,
    portionMatch: 0,
    countMatch: 0,
    countTotal: 0,
    dishCount: 0,
    dishExpected: 0,
    structureMatch: 0,
    panelWrong: [],
    caffeineExpected: null,
    caffeineActual: null,
    missedGroups: [],
    spuriousGroups: [],
    duplicateGroups: [],
    mealStatusOk: null,
    otherMealsOk: null,
    hiddenMissed: [],
    failures: [],
    pass: false,
  };

  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch (error) {
    return {
      ...empty,
      parseError: error instanceof Error ? error.message : String(error),
      failures: ["did not parse"],
    };
  }
  const parsed = evalRecognitionSchema.safeParse(json);
  if (!parsed.success) {
    return { ...empty, parseError: parsed.error.message, failures: ["did not match the schema"] };
  }
  const actual = parsed.data;

  // Hidden items are not in the photograph. A plain run cannot find them and is
  // not marked down for it — but a note run was told, so on that track they are
  // expected like anything else. Without this the note track scores nothing:
  // every hidden item could be missed and the case would still pass.
  const goldenItems = goldenIngredients(golden.dishes);
  const hiddenItems = goldenItems.filter((item) => item.hidden);
  const visible = told ? goldenItems : goldenItems.filter((item) => !item.hidden);
  const actualItems = actual.dishes.flatMap((dish) =>
    dish.ingredients.map((item) => ({ ...item, dish: dish.name })),
  );

  const expectedSet = new Set<string>(visible.map((item) => item.group));
  const actualSet = new Set<string>(actualItems.map((item) => item.group));

  /**
   * A golden item's `alternatives` are rivals the DATASET accepts for it, and
   * answering one of them is a right answer.
   *
   * Only the GOLDEN's alternatives count. Crediting the model's would pay it to
   * hedge, which is exactly what the prompt tells it not to do.
   */
  const acceptedFor = (group: string) =>
    visible.filter((item) => item.group === group).flatMap((item) => item.alternatives ?? []);
  const accepted = new Set<string>([
    ...expectedSet,
    ...visible.flatMap((item) => item.alternatives ?? []),
  ]);
  const hits = [...expectedSet].filter(
    (group) => actualSet.has(group) || acceptedFor(group).some((alt) => actualSet.has(alt)),
  );

  const recall = expectedSet.size === 0 ? 1 : hits.length / expectedSet.size;
  const precision = actualSet.size === 0 ? 0 : hits.length / actualSet.size;

  // Quantity, in servings, because that is the unit the app scores in and the
  // only one both sides can be expressed in.
  //
  // The golden set says `count × size × portion` on a three-step ladder; the
  // model now answers in absolute grams. Comparing the ladder strings to each
  // other used to be the check, and it graded a field nothing scores from — a
  // build could return 300 g of beef as 30 and still pass, because it said
  // "medium" either way.
  //
  // Both sides are converted to servings and the error is judged with a
  // tolerance, since neither side is a measurement: the golden is another
  // model's reading, and agreeing with it to the nearest half serving is as
  // much as the ladder can express.
  const judgeable = visible.filter((item) => actualSet.has(item.group));
  const quantityHits = judgeable.filter((item) => {
    const want = servingsOfGolden(item);
    return actualItems.some((found) => {
      if (found.group !== item.group) return false;
      const got = servingsOfFound(found);
      if (got === null) return found.portion === item.portion;
      return Math.abs(got - want) <= Math.max(0.5, want * 0.4);
    });
  });
  const portionMatch = judgeable.length === 0 ? 1 : quantityHits.length / judgeable.length;

  /**
   * Structure, matched on what is inside a dish rather than on what it is
   * called. "som tam" and "green papaya salad" are the same dish and no string
   * comparison knows it, while two dishes holding the same groups are the same
   * dish whatever either is named.
   */
  const signature = (groups: string[]) => new Set(groups);
  /**
   * How much of the smaller dish the larger one accounts for.
   *
   * Not Jaccard, which punishes a small golden dish against a more decomposed
   * answer: a bubble waffle is one `sweets` and an answer of waffle-plus-ice-
   * cream-plus-sweets shares everything the golden has, yet scores 0.33 and is
   * called a different dish. Union-based similarity answers "are these the same
   * set", and the question here is "is this the same dish".
   */
  const overlap = (a: Set<string>, b: Set<string>) => {
    const shared = [...a].filter((group) => b.has(group)).length;
    const smaller = Math.min(a.size, b.size);
    return smaller === 0 ? 1 : shared / smaller;
  };
  /** Jaccard survives as the tiebreak, so the closest candidate still wins. */
  const sameness = (a: Set<string>, b: Set<string>) => {
    const shared = [...a].filter((group) => b.has(group)).length;
    const union = new Set([...a, ...b]).size;
    return union === 0 ? 1 : shared / union;
  };
  const actualSignatures = actual.dishes.map((dish) =>
    signature(dish.ingredients.map((item) => item.group)),
  );
  const takenDishes = new Set<number>();
  let structureHits = 0;
  const unmatchedDishes: string[] = [];
  for (const dish of golden.dishes) {
    const visibleIngredients = dish.ingredients.filter((item) => told || !item.hidden);
    // The golden's own alternatives are right answers everywhere else in this
    // file, and a dish matched on its groups must honour them too: escargot is
    // declared as `fish` or `other`, and an answer of `other` is not a
    // different dish.
    const want = signature([
      ...visibleIngredients.map((item) => item.group),
      ...visibleIngredients.flatMap((item) => item.alternatives ?? []),
    ]);
    let best = -1;
    let bestScore = 0;
    let bestTie = 0;
    actualSignatures.forEach((have, index) => {
      if (takenDishes.has(index)) return;
      const score = overlap(want, have);
      const tie = sameness(want, have);
      if (score > bestScore || (score === bestScore && tie > bestTie)) {
        bestScore = score;
        bestTie = tie;
        best = index;
      }
    });
    // Half the smaller dish shared is the loosest reading that still means "the
    // same dish": below it, a rice bowl matched against a side salad would count.
    if (best >= 0 && bestScore >= 0.5) {
      takenDishes.add(best);
      structureHits += 1;
    } else {
      unmatchedDishes.push(dish.name);
    }
  }
  const structureMatch = golden.dishes.length === 0 ? 1 : structureHits / golden.dishes.length;

  // Only dishes the golden counts above one are a real test of counting; every
  // other dish is count 1 and answering 1 proves nothing.
  const counted = golden.dishes.filter((dish) => dish.count > 1);
  const countMatch = counted.filter((dish) => {
    const want = signature(dish.ingredients.map((item) => item.group));
    return actual.dishes.some(
      (found) =>
        found.count === dish.count &&
        overlap(want, signature(found.ingredients.map((item) => item.group))) >= 0.5,
    );
  }).length;

  /**
   * A transcribed figure is either right or absent. Being close is the failure
   * mode that matters: a number near the truth is what recall of a familiar
   * product produces, and it is indistinguishable from a reading unless it is
   * checked against what the label actually says.
   */
  const panelWrong: string[] = [];
  for (const dish of golden.dishes) {
    const want = signature(dish.ingredients.map((item) => item.group));
    const found = actual.dishes.find(
      (candidate) => overlap(want, signature(candidate.ingredients.map((i) => i.group))) >= 0.5,
    );
    if (!found) continue;
    if (dish.panel == null) {
      // The golden says nothing is legible here. Any figure is invented.
      const invented = Object.entries(found.panel ?? {}).filter(([, value]) => value != null);
      for (const [field] of invented) panelWrong.push(`${dish.name}: invented ${field}`);
      continue;
    }
    for (const [field, expected] of Object.entries(dish.panel)) {
      if (expected == null) continue;
      const got = (found.panel as Record<string, number | null> | null)?.[field];
      if (got == null) panelWrong.push(`${dish.name}: missed ${field}`);
      else if (Math.abs(got - expected) > 0.05) {
        panelWrong.push(`${dish.name}: ${field} ${got} not ${expected}`);
      }
    }
  }

  const caffeineOf = (dishes: Array<{ count: number; ingredients: Array<{ group: string }> }>) =>
    dishes.reduce(
      (total, dish) =>
        total +
        dish.count *
          dish.ingredients.reduce(
            (perServing, item) => perServing + (CAFFEINE_MG_PER_SERVING[item.group] ?? 0),
            0,
          ),
      0,
    );
  const wantsCaffeine = golden.dishes.some((dish) => dish.caffeine_mg != null);
  const caffeineExpected = wantsCaffeine
    ? golden.dishes.reduce((total, dish) => total + (dish.caffeine_mg ?? 0), 0)
    : null;
  const caffeineActual = wantsCaffeine ? caffeineOf(actual.dishes) : null;

  const missedGroups = [...expectedSet].filter(
    (group) => !actualSet.has(group) && !acceptedFor(group).some((alt) => actualSet.has(alt)),
  );
  const hiddenMissed = told
    ? hiddenItems.filter((item) => !actualSet.has(item.group)).map((item) => item.name)
    : [];
  const mealStatusOk = golden.meal_status ? actual.meal_status === golden.meal_status : null;

  // Gates are rules with an unambiguous right answer. `meal_status` is not one
  // of them: the golden calls a full canteen tray "eaten" and every model calls
  // it "not_yet_eaten", and neither reading is wrong from a photograph.
  const failures: string[] = [];
  if (recall < RECALL_FLOOR) failures.push(`missed ${missedGroups.join(", ")}`);
  if (structureMatch < STRUCTURE_FLOOR) {
    // Name what went unmatched. "grouped 1 dishes where the tray has 1" was
    // true and useless: the counts agreed and the grouping did not.
    failures.push(
      `no dish matched ${unmatchedDishes.join(", ")}` +
        ` (${actual.dishes.length} reported, ${golden.dishes.length} expected)`,
    );
  }
  // Inventing a figure is worse than missing one: the field's only value is
  // that what it holds was read.
  const invented = panelWrong.filter((entry) => entry.includes("invented"));
  if (invented.length > 0) failures.push(invented.join("; "));
  if (told && hiddenMissed.length > 0)
    failures.push(`ignored the note: ${hiddenMissed.join(", ")}`);

  return {
    parsed: true,
    recall,
    precision,
    portionMatch,
    countMatch,
    countTotal: counted.length,
    dishCount: actual.dishes.length,
    dishExpected: golden.dishes.length,
    structureMatch,
    panelWrong,
    caffeineExpected,
    caffeineActual,
    missedGroups,
    // An accepted rival is not spurious either: the golden named it as a
    // defensible reading, so reporting it is not an invented row.
    spuriousGroups: [...actualSet].filter((group) => !accepted.has(group)),
    duplicateGroups: [],
    mealStatusOk,
    otherMealsOk: null,
    hiddenMissed,
    failures,
    // Precision is reporting, not a gate: a spurious item is one tap from being
    // deleted while a missed one is invisible. Everything else here is a rule
    // the prompt states, so failing it is failing.
    pass: failures.length === 0,
  };
}

/** The three-step ladder as servings. */
const LADDER: Record<string, number> = { small: 0.5, medium: 1, large: 2, S: 0.5, M: 1, L: 2 };

/**
 * What the golden annotation claims is present, in servings. The dataset writes
 * quantity as `count × size × portion`, so all three have to come back out.
 */
function servingsOfGolden(item: {
  portion?: string;
  dishCount?: number;
  dishSize?: string;
}): number {
  // `dishCount`/`dishSize`, not `count`/`size` — `goldenIngredients` renames
  // them as it flattens. Reading the wrong names defaults silently to one
  // medium serving, which scores every dish as average and looks like it works.
  const count = item.dishCount ?? 1;
  const size = LADDER[item.dishSize ?? "M"] ?? 1;
  return count * size * (LADDER[item.portion ?? "M"] ?? 1);
}

/**
 * What the model said, in servings. Null when it answered on the ladder alone —
 * a cached answer from before grams were asked for, which is judged the old way
 * rather than scored against a number it never produced.
 */
function servingsOfFound(found: { grams?: number | null; group: string; servings?: number | null }): number | null {
  if (found.grams != null) return found.grams / (SERVING_GRAMS[found.group] ?? 100);
  if (found.servings != null) return found.servings;
  return null;
}

/** Grams in one serving, mirroring `ServingWeight.defaultGrams` in Core. */
const SERVING_GRAMS: Record<string, number> = {
  fish: 100, white_meat: 100, red_meat: 100, processed_meat: 50, egg: 50, dairy: 200,
  legumes: 150, nuts: 30, whole_grains: 150, refined_grains: 150, vegetables: 100,
  fruit: 120, healthy_fats: 30, pastry: 60, sweets: 30, sofrito: 50, butter: 15,
  olive_oil: 10, sugary_drinks: 330, coffee: 200, tea: 200, juice: 200,
  plant_milk: 200, smoothie: 250, alcohol: 330, other: 100,
};
