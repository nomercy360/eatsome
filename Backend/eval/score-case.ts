import { mealRecognitionSchema } from "../src/contracts";
import type { GoldenCase } from "./golden";
import { mapGroup, mapPortion } from "./taxonomy";

/**
 * One answer against one golden case.
 *
 * Deterministic on purpose. The output is a closed enum plus a three-value
 * portion, so recall and precision are set comparisons — paying a model to
 * compare ["fish"] with ["fish"] would add cost, latency and nondeterminism to a
 * question with an exact answer. Judges earn their keep on open text; this is
 * not open text.
 *
 * Items the app's taxonomy cannot express are excluded from the denominator and
 * counted separately. Scoring them as misses would blame the prompt for a gap
 * only a schema change can close — `pnpm eval:coverage` is where that gap
 * belongs.
 */
export type CaseScore = {
  parsed: boolean;
  parseError?: string;
  recall: number;
  precision: number;
  portionMatch: number;
  duplicateGroups: string[];
  /** Golden items with no representable group; not counted against the model. */
  unscorableItems: number;
  missedGroups: string[];
  spuriousGroups: string[];
  pass: boolean;
};

const RECALL_FLOOR = 0.8;

export function scoreCase(golden: GoldenCase, raw: string): CaseScore {
  const empty: CaseScore = {
    parsed: false,
    recall: 0,
    precision: 0,
    portionMatch: 0,
    duplicateGroups: [],
    unscorableItems: 0,
    missedGroups: [],
    spuriousGroups: [],
    pass: false,
  };

  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch (error) {
    return { ...empty, parseError: error instanceof Error ? error.message : String(error) };
  }
  const parsed = mealRecognitionSchema.safeParse(json);
  if (!parsed.success) return { ...empty, parseError: parsed.error.message };

  const actual = parsed.data;
  const actualGroups = actual.items.map((item) => item.group);
  const actualSet = new Set(actualGroups);

  const expected: { group: string; portion: string | null }[] = [];
  let unscorableItems = 0;
  for (const item of golden.golden) {
    const mapping = mapGroup(item.group);
    if (mapping.kind === "unmapped") {
      unscorableItems += 1;
      continue;
    }
    expected.push({ group: mapping.group, portion: mapPortion(item).portion });
  }

  const expectedSet = new Set(expected.map((one) => one.group));
  const hits = [...expectedSet].filter((group) => actualSet.has(group));
  const recall = expectedSet.size === 0 ? 1 : hits.length / expectedSet.size;
  const precision = actualSet.size === 0 ? 0 : hits.length / actualSet.size;

  // Portions are judged only where a portion could be expressed and the group
  // was found; a third of the golden items are counted rather than sized.
  const judgeable = expected.filter((one) => one.portion && actualSet.has(one.group));
  const portionHits = judgeable.filter((one) =>
    actual.items.some((item) => item.group === one.group && item.portion === one.portion),
  );
  const portionMatch = judgeable.length === 0 ? 1 : portionHits.length / judgeable.length;

  const counts = new Map<string, number>();
  for (const group of actualGroups) counts.set(group, (counts.get(group) ?? 0) + 1);

  return {
    parsed: true,
    recall,
    precision,
    portionMatch,
    duplicateGroups: [...counts].filter(([, n]) => n > 1).map(([group]) => group),
    unscorableItems,
    missedGroups: [...expectedSet].filter((group) => !actualSet.has(group)),
    spuriousGroups: [...actualSet].filter((group) => !expectedSet.has(group)),
    // A missed food is invisible in the app; a spurious one is one tap away.
    // Recall is therefore the gate and precision is reporting.
    pass: recall >= RECALL_FLOOR,
  };
}
