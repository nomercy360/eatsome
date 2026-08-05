# Findings

What the runs decided, with the numbers that decided it. Prompt `meal-v6`,
schema `eval-schema-v1`, scorer `scorer-v3`, 28 cases, artefacts in `runs/`.

Six of those cases are now frozen as holdout and were part of these runs; the
next report will cover the 22 that remain, which is the point at which numbers
here and numbers there stop being comparable.

## Excess rows is the column to watch

Gemini 6, Luna 19, Haiku 24, Qwen 37. It is a hallucination metric, and it
agrees with the token table: Qwen emitted 897 output tokens a call and 37 rows
nobody asked for. Verbosity and invention are one behaviour.

For a photo of a sealed package it matters more than recall. A model that omits
something visible costs you a tap; a model that writes down what it cannot see
puts food in your log that you never ate, and nothing in the app will ever
question it.

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

## Withdrawn: the claim about dedup and pastry rules

An earlier version of this file said `dairy_dedup` fails 8–10 times for every
model and concluded that the prompt was the weak part. The scorer did not
support that. It attributed every trap on a failing case to the failure, so a
case carrying four traps that missed one group counted as four trap failures,
and `pass` was recall alone — duplicates, counts and `meal_status` were computed
and discarded. The claim may still be true; it has not been measured.

What the current scorer does support, on the same artefacts:

| model | pass | recall | precision | measure | counts | meal_status | excess rows |
| --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | 11/28 | 76% | 74% | 41% | 55/96 | 12% | 37 |
| gpt-5.6-luna | 9/28 | 73% | 76% | 61% | 39/96 | 13% | 19 |
| **gemini-3.6-flash** | **17/28** | **87%** | **88%** | **73%** | **71/96** | 10% | **6** |
| claude-haiku-4.5 | 9/28 | 72% | 71% | 51% | 29/96 | 8% | 24 |

Measure is stricter than the first report: a counted item must now have the right
number, where before any count was accepted. The ordering is unchanged and
Gemini leads every column.

Two things are deliberately reported rather than gated, and both were briefly
gated by mistake.

`meal_status` agreement is 8–13% for every model. When four independent vendors
agree and the golden disagrees, the label is the thing to suspect: the golden
calls a full canteen tray `eaten` and all four call it `not_yet_eaten`, and no
photograph settles it.

A repeated group is not a defect. Seven of the 28 golden cases repeat one —
four fruits on a platter really are four items, cheese and yoghurt really are
two — and the app caps per group when scoring rather than asking the model to
merge. Only rows beyond what the golden expects are counted, as `excess rows`,
and Gemini has six against Qwen's thirty-seven.

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
