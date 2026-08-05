import type { GoldenCase } from "./golden";
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
  /** Of the groups found, how many also got the measure and value right. */
  portionMatch: number;
  /** Counted items where the number was exactly right. */
  countMatch: number;
  countTotal: number;
  missedGroups: string[];
  spuriousGroups: string[];
  duplicateGroups: string[];
  mealStatusOk: boolean | null;
  otherMealsOk: boolean | null;
  /** Items the golden marks invisible; only reachable with the note slot, so
   *  they are reported rather than counted against a plain photo run. */
  hiddenMissed: string[];
  pass: boolean;
};

const RECALL_FLOOR = 0.8;

export function scoreCase(golden: GoldenCase, raw: string): CaseScore {
  const empty: CaseScore = {
    parsed: false,
    recall: 0,
    precision: 0,
    portionMatch: 0,
    countMatch: 0,
    countTotal: 0,
    missedGroups: [],
    spuriousGroups: [],
    duplicateGroups: [],
    mealStatusOk: null,
    otherMealsOk: null,
    hiddenMissed: [],
    pass: false,
  };

  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch (error) {
    return { ...empty, parseError: error instanceof Error ? error.message : String(error) };
  }
  const parsed = evalRecognitionSchema.safeParse(json);
  if (!parsed.success) return { ...empty, parseError: parsed.error.message };
  const actual = parsed.data;

  // Hidden items are not in the photograph at all. A plain run cannot find them
  // and is not marked down for it; the note-slot track is where they count.
  const visible = golden.golden.filter((item) => !item.hidden);
  const hiddenItems = golden.golden.filter((item) => item.hidden);

  const expectedSet = new Set(visible.map((item) => item.group));
  const actualSet = new Set(actual.items.map((item) => item.group));
  const hits = [...expectedSet].filter((group) => actualSet.has(group));

  const recall = expectedSet.size === 0 ? 1 : hits.length / expectedSet.size;
  const precision = actualSet.size === 0 ? 0 : hits.length / actualSet.size;

  // Measure first, value second: calling a countable thing a size is the error
  // that matters, because it is the one that makes protein unestimable.
  const judgeable = visible.filter((item) => actualSet.has(item.group));
  const measureHits = judgeable.filter((item) =>
    actual.items.some(
      (found) =>
        found.group === item.group &&
        found.measure === item.measure &&
        (item.measure === "size"
          ? found.size === item.size
          : item.measure === "count"
            ? true
            : true),
    ),
  );
  const portionMatch = judgeable.length === 0 ? 1 : measureHits.length / judgeable.length;

  const counted = visible.filter((item) => item.measure === "count");
  const countMatch = counted.filter((item) =>
    actual.items.some(
      (found) =>
        found.group === item.group && found.measure === "count" && found.count === item.count,
    ),
  ).length;

  const counts = new Map<string, number>();
  for (const item of actual.items) counts.set(item.group, (counts.get(item.group) ?? 0) + 1);

  return {
    parsed: true,
    recall,
    precision,
    portionMatch,
    countMatch,
    countTotal: counted.length,
    missedGroups: [...expectedSet].filter((group) => !actualSet.has(group)),
    spuriousGroups: [...actualSet].filter((group) => !expectedSet.has(group)),
    duplicateGroups: [...counts].filter(([, n]) => n > 1).map(([group]) => group),
    mealStatusOk: golden.meal_status ? actual.meal_status === golden.meal_status : null,
    otherMealsOk: null,
    hiddenMissed: hiddenItems.filter((item) => !actualSet.has(item.group)).map((item) => item.name),
    // A missed food is invisible in the app; a spurious one is one tap from
    // being deleted. Recall gates, everything else reports.
    pass: recall >= RECALL_FLOOR,
  };
}
