import { appendFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { loadTextCases } from "./golden-text";
import {
  EVAL_PROMPT_VERSION,
  type EvalModel,
  isConfigured,
  loadModels,
  type RunRecord,
  recognizeTextOnce,
  SCHEMA_VERSION,
} from "./harness";

/**
 * The text-track matrix: described meals, no photographs. Same discipline as
 * `run.ts` — raw answers into `runs/*.jsonl`, scoring elsewhere, three runs
 * because a case that flickers is worse than one that is stably wrong.
 *
 *   GEMINI_API_KEY=… pnpm eval:text [--runs 3] [--model gemini-flash] [--holdout]
 */
const args = process.argv.slice(2);
const flag = (name: string, fallback: string) => {
  const index = args.indexOf(`--${name}`);
  return index === -1 ? fallback : (args[index + 1] ?? fallback);
};

const runsPerCase = Number(flag("runs", "3"));
const concurrency = Number(flag("concurrency", "4"));
const only = args.indexOf("--model") === -1 ? null : flag("model", "");
const includeHoldout = args.includes("--holdout");

const cases = loadTextCases().filter((one) => includeHoldout || !one.holdout);
const models = loadModels()
  .filter((entry) => (only ? entry.id === only : true))
  .filter((entry) => (only ? true : entry.tier === "candidate"))
  .filter((entry) => isConfigured(entry.provider));

if (models.length === 0) {
  console.error(
    "No model is runnable. Set OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY or QWEN_API_KEY.",
  );
  process.exit(1);
}

type Job = { caseId: string; said: string; entry: EvalModel; run: number };
const jobs: Job[] = [];
for (const entry of models) {
  for (const one of cases) {
    for (let run = 1; run <= runsPerCase; run++) {
      jobs.push({ caseId: one.id, said: one.said, entry, run });
    }
  }
}

const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
const output = join(import.meta.dirname, "runs", `${stamp}_${EVAL_PROMPT_VERSION}_text.jsonl`);
writeFileSync(output, "");

console.log(
  `${jobs.length} calls: ${cases.length} text cases × ${models.length} models × ${runsPerCase} runs`,
);
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
      said: job.said,
      track: "text",
      reasoning:
        {
          openai: process.env.OPENAI_REASONING_EFFORT,
          gemini: process.env.GEMINI_THINKING_LEVEL,
          anthropic: process.env.ANTHROPIC_THINKING_BUDGET,
          qwen: process.env.QWEN_ENABLE_THINKING,
          openrouter: undefined,
        }[job.entry.provider] || "default",
      run: job.run,
      ok: false,
    };
    try {
      const result = await recognizeTextOnce(job.entry.provider, job.said, job.entry.model);
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

await Promise.all(Array.from({ length: concurrency }, () => worker(jobs)));
console.log(`\n\nwrote ${output}\nnow: pnpm eval:text:score`);
