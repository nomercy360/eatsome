# Eval

28 photos, human golden, four candidate models. Run it after any prompt change.

```bash
pnpm eval:coverage   # what the dataset asks for that the app cannot express
pnpm eval            # candidates, three runs each, via promptfoo
pnpm eval:ceiling    # the expensive tier — reference only, never gates
pnpm eval:holdout    # the cases held back from prompt iteration
```

Keys come from the environment: `OPENAI_API_KEY`, `GEMINI_API_KEY`,
`ANTHROPIC_API_KEY`, `QWEN_API_KEY`. Models that have no key are skipped.

## Why the providers are ours

`eval/promptfoo-provider.ts` calls `worker/ai/*`, the same code the proxy runs.
Pointed at promptfoo's built-in providers instead, the eval would measure
promptfoo's request shaping — and the four vendors differ exactly where it
matters: strict `json_schema`, `responseSchema`, a forced `tool_use` call, and an
OpenAI-compatible endpoint that implements none of the above the same way.

Same reason the prompt is not in this directory. It is `prompts/meal-v5.md`,
generated into both languages, with tests either side that fail on drift.

## Four things this is built to avoid

- **Fitting the prompt to the dataset.** Some cases are holdout: excluded from
  every ordinary run, looked at only when a version is otherwise finished. Ten
  iterations of staring at failures is enough to learn 28 photos.
- **Contaminated few-shot examples.** If a prompt ever carries examples, they
  come from photos that are not in here. An example of a case you also score
  measures memory.
- **Scoring welded to running.** `run.ts` writes raw answers to `runs/*.jsonl`
  and scores nothing. Dedup rules will change; re-scoring an artefact is free,
  re-running the matrix is not.
- **Averages on 28 cases.** A three-point move in recall is one photo. The report
  that matters is which cases flipped between prompt versions.

## Metrics, and why no judge

Group recall and precision, portion match, duplicate groups. All set comparisons
against a closed enum — there is an exact answer, so a model-graded assertion
would add cost, latency and nondeterminism to a question that does not need an
opinion. A judge earns its keep on open text.

Recall gates: a missed food is invisible in the app, while a spurious one is one
tap from being deleted.

## The taxonomy gap

The golden set is richer than `FoodGroup`, and `pnpm eval:coverage` prints the
difference. Items with no representable group are excluded from the denominator
rather than counted as misses — otherwise every model "fails" a potato for a
reason no prompt can fix. Read that report before believing any number here.
