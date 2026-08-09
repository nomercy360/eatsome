import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadTextCases, type TextCase } from "./golden-text";
import type { RunRecord } from "./harness";
import { evalRecognitionSchema } from "./schema";
import { SCORER_VERSION, scoreCase } from "./score-case";

/**
 * Scores a text-track artefact. No API calls, same reasons as `score.ts`.
 *
 * `scoreCase` does the shared work — groups, weights, structure, panels — and
 * this file adds the three checks only a described meal can be asked:
 *
 * - `other_meals_visible` must be false. Nothing stood behind the words to
 *   skip, and true here means the model is still narrating a photograph.
 * - none of the case's `forbidden_groups` may appear. A described meal has no
 *   background, so the drink or side the person never mentioned is invention,
 *   not perception — and it gates, because a furnished meal scores food nobody
 *   ate.
 * - each `expected_forks` pair should surface: some answered item holding one
 *   rival with another in its `alternatives`. That is the fork the client can
 *   turn into a question ("butter — or oil?"), and an answer that silently
 *   commits has hidden a decision the person should have been offered.
 *   Reported AND gated, because the fork is the case's reason to exist.
 *
 *   pnpm eval:text:score [file.jsonl]
 */
const runsDir = join(import.meta.dirname, "runs");
const args = process.argv.slice(2);
const explicit = args.find((arg) => arg.endsWith(".jsonl"));
const artefacts = readdirSync(runsDir)
  .filter((name) => name.endsWith("_text.jsonl"))
  .sort();

const file = explicit ?? artefacts.at(-1);
if (!file) {
  console.error("No text run artefacts. Try: pnpm eval:text");
  process.exit(1);
}

const rows = readFileSync(join(runsDir, file), "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line) as RunRecord);

const cases = new Map(loadTextCases().map((one) => [one.id, one]));

type TextScore = {
  pass: boolean;
  failures: string[];
  recall: number;
  weightMatch: number;
};

function scoreTextRow(golden: TextCase, raw: string): TextScore {
  const base = scoreCase(golden, raw);
  const failures = [...base.failures];

  const parsed = evalRecognitionSchema.safeParse(
    (() => {
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    })(),
  );
  if (parsed.success) {
    const answer = parsed.data;
    if (answer.other_meals_visible) {
      failures.push("other_meals_visible on a meal that was described, not photographed");
    }
    const answeredGroups = new Set<string>(
      answer.dishes.flatMap((dish) => dish.ingredients.map((item) => item.group)),
    );
    const furnished = (golden.forbidden_groups ?? []).filter((group) => answeredGroups.has(group));
    if (furnished.length > 0) failures.push(`furnished the meal with ${furnished.join(", ")}`);

    for (const fork of golden.expected_forks ?? []) {
      const surfaced = answer.dishes.some((dish) =>
        dish.ingredients.some(
          (item) =>
            fork.includes(item.group) &&
            item.alternatives.some((alt) => fork.includes(alt) && alt !== item.group),
        ),
      );
      if (!surfaced) failures.push(`silently committed on ${fork.join(" vs ")}`);
    }
  }

  return {
    pass: failures.length === 0,
    failures,
    recall: base.recall,
    weightMatch: base.weightMatch,
  };
}

type ModelReport = {
  runs: number;
  errors: number;
  passes: number;
  recall: number;
  weightMatch: number;
  failing: Map<string, string[]>;
};

const byModel = new Map<string, ModelReport>();
for (const row of rows) {
  const golden = cases.get(row.caseId);
  if (!golden) continue;
  const report = byModel.get(row.modelId) ?? {
    runs: 0,
    errors: 0,
    passes: 0,
    recall: 0,
    weightMatch: 0,
    failing: new Map(),
  };
  report.runs += 1;
  if (!row.ok || !row.raw) {
    report.errors += 1;
    report.failing.set(row.caseId, [
      ...(report.failing.get(row.caseId) ?? []),
      row.error ?? "no answer",
    ]);
  } else {
    const score = scoreTextRow(golden, row.raw);
    report.recall += score.recall;
    report.weightMatch += score.weightMatch;
    if (score.pass) report.passes += 1;
    else {
      report.failing.set(row.caseId, [
        ...(report.failing.get(row.caseId) ?? []),
        ...score.failures,
      ]);
    }
  }
  byModel.set(row.modelId, report);
}

console.log(`${file} under ${SCORER_VERSION}\n`);
for (const [modelId, report] of byModel) {
  const answered = report.runs - report.errors;
  console.log(
    `${modelId}: ${report.passes}/${report.runs} pass` +
      (answered > 0
        ? `, recall ${(report.recall / answered).toFixed(2)}, weights ${(
            report.weightMatch / answered
          ).toFixed(2)}`
        : "") +
      (report.errors > 0 ? `, ${report.errors} errors` : ""),
  );
  for (const [caseId, failures] of report.failing) {
    console.log(`  ${caseId}: ${[...new Set(failures)].join("; ")}`);
  }
  console.log();
}
