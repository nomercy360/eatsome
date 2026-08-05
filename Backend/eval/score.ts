import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadGoldenCases } from "./golden";
import type { RunRecord } from "./harness";
import { loadModels } from "./harness";
import { scoreCase } from "./score-case";

/**
 * Artefacts in, report out. No API calls.
 *
 * Scoring rules will change — the dedup rule certainly will — and re-scoring a
 * committed run costs nothing while re-running the matrix costs money and an
 * hour. Which is also why the report leads with flips rather than averages: on
 * 28 cases a three-point move in recall is one photo, and the useful sentence is
 * "IMG_3181 went pass to fail", not "recall fell 3%".
 *
 *   pnpm eval:score [file.jsonl] [--against previous.jsonl]
 */
const runsDir = join(import.meta.dirname, "runs");
const args = process.argv.slice(2);
const flagIndex = args.indexOf("--against");
const baselineFile = flagIndex === -1 ? null : args[flagIndex + 1];
const explicit = args.find((arg) => arg.endsWith(".jsonl"));
const artefacts = readdirSync(runsDir)
  .filter((name) => name.endsWith(".jsonl"))
  .sort();

if (artefacts.length === 0) {
  console.error("No run artefacts. Try: pnpm eval:run");
  process.exit(1);
}

/**
 * A row belongs to a run only if it was produced under the same configuration.
 *
 * Filenames are not enough. Models arrive one key at a time, so several files
 * are one run — but reasoning experiments and note runs share those filenames
 * too, and merging them silently rewrites history: the Haiku thinking
 * experiment's errors dragged its committed 10/28 to 0/28 while a Gemini
 * high-thinking pass inflated its cost, in a report that named neither.
 */
function fingerprint(row: RunRecord): string {
  return [
    row.promptVersion,
    row.schemaVersion ?? "-",
    row.reasoning ?? "default",
    row.note ? "notes" : "plain",
  ].join("|");
}

const wanted = args.indexOf("--config") === -1 ? null : args[args.indexOf("--config") + 1];

const cases = loadGoldenCases();
const models = loadModels();

function read(files: string | string[]): RunRecord[] {
  return (Array.isArray(files) ? files : [files]).flatMap((file) =>
    readFileSync(join(runsDir, file), "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line) as RunRecord),
  );
}

type Summary = {
  modelId: string;
  tier: string;
  runs: number;
  errors: number;
  recall: number;
  precision: number;
  portionMatch: number;
  countMatch: number;
  countTotal: number;
  statusOk: number;
  statusKnown: number;
  /** Rows beyond what the golden expects for that group. */
  excessRows: number;
  counts: string;
  usd: number;
  /** Cases that did not agree with themselves across repeats. Nondeterminism at
   *  temperature zero is real, and a case that flickers is worse than one that
   *  is stably wrong: you cannot fix what you cannot reproduce. */
  unstable: string[];
  /** caseId → passed in every run */
  perCase: Map<string, boolean>;
  trapFailures: Map<string, number>;
  /** Why cases failed, which is actionable where a trap name is only a label. */
  reasons: Map<string, number>;
};

function summarise(records: RunRecord[]): Map<string, Summary> {
  const byModel = new Map<string, Summary>();
  for (const record of records) {
    const entry = models.find((one) => one.id === record.modelId);
    const summary = byModel.get(record.modelId) ?? {
      modelId: record.modelId,
      tier: record.tier ?? "candidate",
      runs: 0,
      errors: 0,
      recall: 0,
      precision: 0,
      portionMatch: 0,
      countMatch: 0,
      countTotal: 0,
      statusOk: 0,
      statusKnown: 0,
      excessRows: 0,
      counts: "",
      usd: 0,
      unstable: [],
      perCase: new Map<string, boolean>(),
      trapFailures: new Map<string, number>(),
      reasons: new Map<string, number>(),
    };
    byModel.set(record.modelId, summary);

    summary.runs += 1;
    if (entry) {
      summary.usd +=
        ((record.inputTokens ?? 0) * entry.usdPerMillionInput) / 1e6 +
        ((record.outputTokens ?? 0) * entry.usdPerMillionOutput) / 1e6;
    }
    if (!record.ok || !record.raw) {
      summary.errors += 1;
      summary.perCase.set(record.caseId, false);
      continue;
    }

    const golden = cases.find((one) => one.id === record.caseId);
    if (!golden) continue;
    const score = scoreCase(golden, record.raw, record.note);
    summary.recall += score.recall;
    summary.precision += score.precision;
    summary.portionMatch += score.portionMatch;
    summary.countMatch += score.countMatch;
    summary.countTotal += score.countTotal;
    summary.excessRows += score.duplicateGroups.length;
    if (score.mealStatusOk !== null) {
      summary.statusKnown += 1;
      if (score.mealStatusOk) summary.statusOk += 1;
    }

    const previous = summary.perCase.get(record.caseId);
    if (previous !== undefined && previous !== score.pass) {
      if (!summary.unstable.includes(record.caseId)) summary.unstable.push(record.caseId);
    }
    summary.perCase.set(record.caseId, (previous ?? true) && score.pass);

    // Only traps on a failing case, and the reason recorded alongside — a case
    // carrying four traps that missed one group is not four trap failures.
    if (!score.pass) {
      for (const reason of score.failures) {
        summary.reasons.set(
          reason.split(" ")[0] ?? reason,
          (summary.reasons.get(reason.split(" ")[0] ?? reason) ?? 0) + 1,
        );
      }
      for (const trap of golden.traps) {
        summary.trapFailures.set(trap, (summary.trapFailures.get(trap) ?? 0) + 1);
      }
    }
  }
  return byModel;
}

const all = explicit ? read(explicit) : artefacts.flatMap((file) => read(file));
const configurations = [...new Set(all.map(fingerprint))].sort();
// Default to the plain, default-reasoning configuration: the one a bare
// `pnpm eval:run` produces and the one every claim in FINDINGS.md is about.
const configuration =
  wanted ?? configurations.find((one) => one.endsWith("default|plain")) ?? configurations[0];
const rows = all.filter((row) => fingerprint(row) === configuration);

const current = summarise(rows);
const baseline = baselineFile
  ? summarise(read(baselineFile).filter((row) => fingerprint(row) === configuration))
  : null;

const lines: string[] = [];
lines.push(`# Eval report\n`);
lines.push(
  `Configuration \`${configuration}\`${baselineFile ? ` against \`${baselineFile}\`` : ""}.`,
);
lines.push(`${rows.length} outputs over ${cases.length} cases.\n`);
if (configurations.length > 1) {
  lines.push(
    `Excluded, because they were produced under a different configuration: ${configurations
      .filter((one) => one !== configuration)
      .map((one) => `\`${one}\``)
      .join(", ")}. Select one with \`--config\`.\n`,
  );
}

lines.push(`## Models\n`);
lines.push(
  `Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.\n`,
);
lines.push(
  `| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |`,
);
lines.push(`| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |`);
for (const summary of [...current.values()].sort((a, b) => a.usd - b.usd)) {
  const scored = summary.runs - summary.errors || 1;
  const passed = [...summary.perCase.values()].filter(Boolean).length;
  lines.push(
    `| ${summary.modelId} | ${summary.tier} | ${passed}/${summary.perCase.size} | ` +
      `${((summary.recall / scored) * 100).toFixed(0)}% | ` +
      `${((summary.precision / scored) * 100).toFixed(0)}% | ` +
      `${((summary.portionMatch / scored) * 100).toFixed(0)}% | ` +
      `${summary.countTotal ? `${summary.countMatch}/${summary.countTotal}` : "—"} | ` +
      `${summary.statusKnown ? `${((summary.statusOk / summary.statusKnown) * 100).toFixed(0)}%` : "—"} | ` +
      `${summary.excessRows} | ` +
      `${summary.errors} | $${summary.usd.toFixed(3)} |`,
  );
}

lines.push(`\n## Flips\n`);
if (!baseline) {
  lines.push(`No baseline given. Re-run with \`--against <earlier.jsonl>\` to see movement.\n`);
} else {
  let any = false;
  for (const [modelId, summary] of current) {
    const before = baseline.get(modelId);
    if (!before) continue;
    for (const [caseId, passed] of summary.perCase) {
      const was = before.perCase.get(caseId);
      if (was === undefined || was === passed) continue;
      any = true;
      const golden = cases.find((one) => one.id === caseId);
      lines.push(
        `- **${modelId}** ${caseId}: ${was ? "pass→fail" : "fail→pass"} (${golden?.traps.join(", ") ?? ""})`,
      );
    }
  }
  if (!any) lines.push(`Nothing flipped.\n`);
}

lines.push(`\n## Unstable across repeats\n`);
for (const summary of current.values()) {
  if (summary.unstable.length === 0) continue;
  lines.push(`- **${summary.modelId}**: ${summary.unstable.join(", ")}`);
}
if ([...current.values()].every((one) => one.unstable.length === 0)) {
  lines.push(`None — every case agreed with itself across repeats.`);
}

lines.push(`\n## Why cases failed\n`);
for (const summary of current.values()) {
  const worst = [...summary.reasons].sort((a, b) => b[1] - a[1]);
  if (worst.length === 0) continue;
  lines.push(`\n**${summary.modelId}**: ${worst.map(([r, n]) => `${r} ${n}`).join(", ")}`);
}

lines.push(`\n## Traps carried by failing cases\n`);
lines.push(
  `A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.\n`,
);
for (const summary of current.values()) {
  const worst = [...summary.trapFailures].sort((a, b) => b[1] - a[1]).slice(0, 12);
  if (worst.length === 0) continue;
  lines.push(`\n**${summary.modelId}**\n`);
  for (const [trap, count] of worst) lines.push(`- ${trap} — ${count}`);
}

const report = `${lines.join("\n")}\n`;
writeFileSync(join(import.meta.dirname, "report.md"), report);
console.log(report);

// The gate acts on candidates only: a ceiling model exists to say whether there
// is headroom, not to decide whether a prompt ships.
const regressions = baseline
  ? [...current.values()].filter(
      (summary) =>
        summary.tier === "candidate" &&
        [...summary.perCase].some(
          ([caseId, passed]) => !passed && baseline.get(summary.modelId)?.perCase.get(caseId),
        ),
    )
  : [];
if (regressions.length > 0) {
  console.error(`\nRegression: ${regressions.map((one) => one.modelId).join(", ")}`);
  process.exit(1);
}
