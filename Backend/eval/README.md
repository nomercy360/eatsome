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

- **Fitting the prompt to the dataset.** Six cases are frozen — one per failure
  class, chosen before the first prompt edit — and excluded from every ordinary
  run. Ten iterations of staring at failures is enough to learn 22 photos, and
  these are the only evidence left that a version generalises rather than having
  been fitted. Run them with `--holdout` when a version is otherwise finished,
  and if they disagree with the dev set, believe them.
- **Contaminated few-shot examples.** If a prompt ever carries examples, they
  come from photos that are not in here. An example of a case you also score
  measures memory.
- **Scoring welded to running.** `run.ts` writes raw answers to `runs/*.jsonl`
  and scores nothing. Dedup rules will change; re-scoring an artefact is free,
  re-running the matrix is not.
- **Averages on 28 cases.** A three-point move in recall is one photo. The report
  that matters is which cases flipped between prompt versions.

## The scorer is versioned too

`SCORER_VERSION` moves whenever a gate, a denominator or a definition does, and
every report names it. Gemini read 21/28, then 17/28, then 21/28 across one
afternoon without answering a single photo differently — the ruler changed twice.
Numbers from two scorer versions are no more comparable than numbers from two
prompts, and nothing else in a report would say which ruler produced it.

The image boundary is versioned for the same reason. New runs render historical
source photos as `jpeg-1024-q82-v1` and record both that version and the actual
SHA-256. Future production cases should copy the exact private R2 model-input
bytes; they must not be reconstructed from a Photos original.

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

## The eval runs ahead of the app

The models are asked for `prompts/meal-v6.md` and `eval/schema.ts`, not the
contract the app ships. The dataset was written from real meals and knows about
potatoes, counted eggs, sauces as their own category and non-wine alcohol; the
app does not yet. While it is being built, the dataset is the one to believe, and
whatever survives these runs is what `FoodGroup` should become.

Two consequences:

- a miss here is a real model failure. Under the production contract, scoring a
  potato as missing blamed the prompt for something no prompt could fix;
- numbers from a v6 run and a v5 run are not comparable. Every row carries both
  `promptVersion` and `schemaVersion` so that stays visible.

`pnpm eval:coverage` now lists the app's debt rather than the dataset's: the
groups and measures still missing from `FoodGroup`, which is the migration list
for after the first results.
