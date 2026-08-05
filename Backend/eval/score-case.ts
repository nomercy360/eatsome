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
  /** Items the golden marks invisible. Excluded from a plain photo run, which
   *  cannot see them, and required on a note run, which was told about them. */
  hiddenMissed: string[];
  /** Why the case failed, in the order the checks run. Empty means it passed. */
  failures: string[];
  pass: boolean;
};

const RECALL_FLOOR = 0.8;

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
 */
export const SCORER_VERSION = "scorer-v3-2026-08-05";

/**
 * `note` is the line the run sent with the photo. It changes what counts: told
 * about the butter, a model that omits it has failed, and a model that finds it
 * without being told was guessing.
 */
export function scoreCase(golden: GoldenCase, raw: string, note?: string | null): CaseScore {
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
  const told = Boolean(note?.trim());
  const hiddenItems = golden.golden.filter((item) => item.hidden);
  const visible = told ? golden.golden : golden.golden.filter((item) => !item.hidden);

  const expectedSet = new Set<string>(visible.map((item) => item.group));
  const actualSet = new Set<string>(actual.items.map((item) => item.group));
  const hits = [...expectedSet].filter((group) => actualSet.has(group));

  const recall = expectedSet.size === 0 ? 1 : hits.length / expectedSet.size;
  const precision = actualSet.size === 0 ? 0 : hits.length / actualSet.size;

  // Measure first, value second: calling a countable thing a size is the error
  // that matters, because it is the one that makes protein unestimable.
  const judgeable = visible.filter((item) => actualSet.has(item.group));
  // The value has to match too. Accepting any count for a counted item gave
  // measure credit to answers that said "three eggs" about one egg.
  const measureHits = judgeable.filter((item) =>
    actual.items.some(
      (found) =>
        found.group === item.group &&
        found.measure === item.measure &&
        (item.measure === "size"
          ? found.size === item.size
          : item.measure === "count"
            ? found.count === item.count
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

  // A repeated group is not a defect by itself: seven of the golden cases repeat
  // one, because four fruits on a platter really are four items and the app caps
  // them at scoring time rather than asking the model to merge them. Only rows
  // beyond what the golden expects are excess.
  const emitted = new Map<string, number>();
  for (const item of actual.items) emitted.set(item.group, (emitted.get(item.group) ?? 0) + 1);
  const wanted = new Map<string, number>();
  for (const item of visible) wanted.set(item.group, (wanted.get(item.group) ?? 0) + 1);
  const duplicateGroups = [...emitted]
    .filter(([group, n]) => n > Math.max(1, wanted.get(group) ?? 1))
    .map(([group]) => group);

  const missedGroups = [...expectedSet].filter((group) => !actualSet.has(group));
  const hiddenMissed = told
    ? hiddenItems.filter((item) => !actualSet.has(item.group)).map((item) => item.name)
    : [];
  const mealStatusOk = golden.meal_status ? actual.meal_status === golden.meal_status : null;

  // Everything that was already being computed and then thrown away. A pass
  // that ignores duplicates, meal status and counts is a pass that cannot
  // support a claim about dedup rules.
  // Gates are rules with an unambiguous right answer. `meal_status` is not one
  // of them: the golden calls a full canteen tray "eaten" and every model calls
  // it "not_yet_eaten", and neither reading is wrong from a photograph. It is
  // reported instead, because 55% disagreement is a finding about the labels.
  const failures: string[] = [];
  if (recall < RECALL_FLOOR) failures.push(`missed ${missedGroups.join(", ")}`);
  if (duplicateGroups.length > 0) failures.push(`duplicated ${duplicateGroups.join(", ")}`);
  if (told && hiddenMissed.length > 0)
    failures.push(`ignored the note: ${hiddenMissed.join(", ")}`);

  return {
    parsed: true,
    recall,
    precision,
    portionMatch,
    countMatch,
    countTotal: counted.length,
    missedGroups,
    spuriousGroups: [...actualSet].filter((group) => !expectedSet.has(group)),
    duplicateGroups,
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
