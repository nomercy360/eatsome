# Findings

What the runs decided, with the numbers that decided it. Prompt `meal-v6`,
schema `eval-schema-v1`, 28 cases, artefacts in `runs/`.

## Gemini 3.6 Flash wins, and not narrowly

| model | pass | recall | precision | measure | $/full run |
| --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | 14/28 | 76% | 74% | 50% | $0.016 |
| gpt-5.6-luna | 13/28 | 73% | 76% | 68% | $0.069 |
| **gemini-3.6-flash** | **21/28** | **87%** | **88%** | **78%** | $0.387 |
| claude-haiku-4.5 | 10/28 | 72% | 71% | 70% | $0.512 |

McNemar on paired cases: against Haiku 13–1 (p=0.002), against Qwen 9–1
(p=0.022), against Luna 7–1 (p=0.070). The ranking holds at every pass
threshold from 0.6 to 1.0, so it is not an artefact of where the line was drawn.

## More reasoning does not help this task

The winner emits the fewest tokens. Gemini at 151 output tokens beats Qwen at
897 by seven cases, in half the latency.

| config | pass | recall | out | latency |
| --- | --- | --- | --- | --- |
| gemini low, 1 run | 24/28 | 91% | 148 | 5.2s |
| gemini high, 1 run | 22/28 | 85% | 169 | 10.6s |
| haiku forced tool, no thinking | 13/28 | 74% | 399 | 4.9s |
| haiku auto tool, 3k thinking | 15/26 | 76% | 2066 | 21.2s |

Gemini at `high` is not better — and the control is that the same config over
one run versus three differs by the same two cases, so that gap is the size of
run-to-run noise while the doubled latency is not.

Haiku with thinking gains two points of recall, which is noise, for five times
the tokens, four times the latency, two outright `max_tokens` failures, and the
loss of guaranteed schema compliance — Anthropic refuses extended thinking
alongside a forced tool call. At 2066 output tokens that is about $1.48 per user
per month, more than a Sonnet-class model, for results fifteen points below
Gemini at half the price. The gap is capability on this task, not budget.

Which fits what the task is. Naming what is on a plate is perception, not
inference: there is little to reason about and the answer is either visible or
it is not.

## The prompt is the weak part, not the model

`dairy_dedup` fails 8–10 times for every model. `homemade_vs_commercial_pastry`
fails exactly 6 times for all four. Four independent vendors failing the same
rule at the same rate is an instruction defect, and fixing those two is worth
more than any model swap — including for Gemini's remaining seven failures.

## Three cases nothing passes

No model reached 0.8 mean recall on `IMG_3165`, `IMG_3167`, `IMG_3171`. When
four vendors agree and the golden disagrees, suspect the label. `IMG_3171` asks
for OCR of Korean packaging in a shop, which is a different task from reading a
plate.

## What is not measured yet

- **Holdout.** All 28 are dev set. Freeze about six before the first prompt edit,
  or the next report measures memorisation.
- **Label provenance.** The golden was drafted by a model. Until the cases where
  Gemini and Qwen disagree are checked by hand, this measures agreement with the
  annotator as much as correctness.
- **The correction prompt.** `MealRevisionPrompt` is Swift-only and the proxy has
  no refine endpoint, so the delta path — the one guarding that hand edits
  survive — is untested.
- **The note track.** Wired (`--notes`), not yet run.
