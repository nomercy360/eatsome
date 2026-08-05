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
const target =
  args.find((arg) => arg.endsWith(".jsonl")) ??
  readdirSync(runsDir)
    .filter((name) => name.endsWith(".jsonl"))
    .sort()
    .at(-1);

if (!target) {
  console.error("No run artefacts. Try: pnpm eval:run");
  process.exit(1);
}

const cases = loadGoldenCases();
const models = loadModels();

function read(file: string): RunRecord[] {
  return readFileSync(join(runsDir, file), "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line) as RunRecord);
}

type Summary = {
  modelId: string;
  tier: string;
  runs: number;
  errors: number;
  recall: number;
  precision: number;
  portionMatch: number;
  counts: string;
  usd: number;
  /** Cases that did not agree with themselves across repeats. Nondeterminism at
   *  temperature zero is real, and a case that flickers is worse than one that
   *  is stably wrong: you cannot fix what you cannot reproduce. */
  unstable: string[];
  /** caseId → passed in every run */
  perCase: Map<string, boolean>;
  trapFailures: Map<string, number>;
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
      counts: "",
      usd: 0,
      unstable: [],
      perCase: new Map<string, boolean>(),
      trapFailures: new Map<string, number>(),
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
    const score = scoreCase(golden, record.raw);
    summary.recall += score.recall;
    summary.precision += score.precision;
    summary.portionMatch += score.portionMatch;

    const previous = summary.perCase.get(record.caseId);
    if (previous !== undefined && previous !== score.pass) {
      if (!summary.unstable.includes(record.caseId)) summary.unstable.push(record.caseId);
    }
    summary.perCase.set(record.caseId, (previous ?? true) && score.pass);

    if (!score.pass) {
      for (const trap of golden.traps) {
        summary.trapFailures.set(trap, (summary.trapFailures.get(trap) ?? 0) + 1);
      }
    }
  }
  return byModel;
}

const current = summarise(read(target));
const baseline = baselineFile ? summarise(read(baselineFile)) : null;

const lines: string[] = [];
lines.push(`# Eval report\n`);
lines.push(`Run \`${target}\`${baselineFile ? ` against \`${baselineFile}\`` : ""}.`);
lines.push(`${cases.length} cases, ${models.length} models known.\n`);

lines.push(`## Models\n`);
lines.push(`| model | tier | pass | recall | precision | measure | errors | $ |`);
lines.push(`| --- | --- | --- | --- | --- | --- | --- | --- |`);
for (const summary of [...current.values()].sort((a, b) => a.usd - b.usd)) {
  const scored = summary.runs - summary.errors || 1;
  const passed = [...summary.perCase.values()].filter(Boolean).length;
  lines.push(
    `| ${summary.modelId} | ${summary.tier} | ${passed}/${summary.perCase.size} | ` +
      `${((summary.recall / scored) * 100).toFixed(0)}% | ` +
      `${((summary.precision / scored) * 100).toFixed(0)}% | ` +
      `${((summary.portionMatch / scored) * 100).toFixed(0)}% | ` +
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

lines.push(`\n## Failures by trap\n`);
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
