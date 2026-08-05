import { appendFileSync, existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { loadGoldenCases } from "./golden";
import {
  EVAL_PROMPT_VERSION,
  type EvalModel,
  isConfigured,
  loadModels,
  noteFor,
  photoPath,
  type RunRecord,
  recognizeOnce,
  SCHEMA_VERSION,
} from "./harness";

/**
 * Runs the matrix and writes raw answers. It scores nothing.
 *
 * The split is deliberate: scoring rules will change — the dedup rule certainly
 * will — and re-scoring an artefact costs nothing while re-running the matrix
 * costs money and an hour. The JSONL files are committed, so a prompt version
 * from three weeks ago can still be re-measured under today's rules.
 *
 *   OPENAI_API_KEY=… pnpm eval:run [--runs 3] [--provider gemini] [--concurrency 4]
 */
const args = process.argv.slice(2);
const flag = (name: string, fallback: string) => {
  const index = args.indexOf(`--${name}`);
  return index === -1 ? fallback : (args[index + 1] ?? fallback);
};

const runsPerCase = Number(flag("runs", "3"));
const concurrency = Number(flag("concurrency", "4"));
const only = args.indexOf("--model") === -1 ? null : flag("model", "");
const includeCeiling = args.includes("--ceiling");
// The note track: same photos, same models, plus the line the person would have
// typed. Scored separately — a hidden ingredient found without a note would be
// a hallucination that happened to be right.
const withNotes = args.includes("--notes");
// Holdout cases are excluded from every ordinary run. They answer whether a
// prompt generalises, and that answer is spent the moment you have iterated
// against their failures.
const includeHoldout = args.includes("--holdout");

const cases = loadGoldenCases();
const models = loadModels()
  .filter((entry) => (only ? entry.id === only : true))
  // Ceiling rows cost the same cents to run and answer a different question, so
  // they are opt-in rather than part of every pass.
  .filter((entry) => (includeCeiling || only ? true : entry.tier === "candidate"))
  .filter((entry) => isConfigured(entry.provider));

if (models.length === 0) {
  console.error(
    "No model is runnable. Set OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY or QWEN_API_KEY.",
  );
  process.exit(1);
}

const missing = cases.filter((one) => !existsSync(photoPath(one.photo)));
if (missing.length > 0) {
  // Named, never skipped silently: a case with no photo is a case that is not
  // being measured, and a report that hides that reads as coverage it does not
  // have.
  console.warn(
    `Missing photos, these cases will not run:\n  ${missing.map((c) => c.photo).join("\n  ")}`,
  );
}
const runnable = cases
  .filter((one) => includeHoldout || !one.holdout)
  .filter((one) => existsSync(photoPath(one.photo)));

type Job = { caseId: string; photo: string; entry: EvalModel; run: number; note?: string };
const jobs: Job[] = [];
for (const entry of models) {
  for (const one of runnable) {
    for (let run = 1; run <= runsPerCase; run++) {
      const note = withNotes ? noteFor(one.golden.filter((item) => item.hidden)) : undefined;
      jobs.push({ caseId: one.id, photo: one.photo, entry, run, note });
    }
  }
}

const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
const output = join(import.meta.dirname, "runs", `${stamp}_${EVAL_PROMPT_VERSION}.jsonl`);
writeFileSync(output, "");

console.log(
  `${jobs.length} calls: ${runnable.length} cases × ${models.length} models × ${runsPerCase} runs`,
);
console.log(`models: ${models.map((entry) => `${entry.id} (${entry.tier})`).join(", ")}`);
console.log(`prompt ${EVAL_PROMPT_VERSION} → ${output}\n`);

let done = 0;
async function worker(queue: Job[]) {
  for (;;) {
    const job = queue.shift();
    if (!job) return;
    const record: RunRecord = {
      caseId: job.caseId,
      modelId: job.entry.id,
      tier: job.entry.tier,
      provider: job.entry.provider,
      model: job.entry.model,
      promptVersion: EVAL_PROMPT_VERSION,
      schemaVersion: SCHEMA_VERSION,
      note: job.note ?? null,
      reasoning:
        {
          openai: process.env.OPENAI_REASONING_EFFORT,
          gemini: process.env.GEMINI_THINKING_LEVEL,
          anthropic: process.env.ANTHROPIC_THINKING_BUDGET,
          qwen: process.env.QWEN_ENABLE_THINKING,
        }[job.entry.provider] || "default",
      run: job.run,
      ok: false,
    };
    try {
      const result = await recognizeOnce(job.entry.provider, job.photo, job.entry.model, job.note);
      Object.assign(record, { ok: true, ...result });
    } catch (error) {
      record.error = error instanceof Error ? error.message : String(error);
    }
    appendFileSync(output, `${JSON.stringify(record)}\n`);
    done += 1;
    process.stdout.write(
      `\r${done}/${jobs.length}${record.ok ? "" : `  last failed: ${record.error}`}`,
    );
  }
}

// Three runs at temperature zero because vision models are not deterministic
// there either. A case that flickers between runs is worse than one that is
// stably wrong, and only repetition shows the difference.
await Promise.all(Array.from({ length: concurrency }, () => worker(jobs)));
console.log(`\n\nwrote ${output}\nnow: pnpm eval:score`);
