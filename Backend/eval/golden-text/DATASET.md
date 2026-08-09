# eatsome text-track dataset v1.1

v1.1 (same day): the first scored run corrected the dataset, not the models.
All three candidates identically "failed" two cases by merging dishes the
golden split — "meat curry with rice" as one plate, powders in water as one
shake — and a dish boundary that words underdetermine belongs to the model's
judgement, so those goldens now hold the merged reading (which the overlap
matcher also accepts split). TXT_001's soup vegetables moved to `hidden`, by
this file's own definition of the word: they are not in the words. The fork
gate's failures stayed — two of three models silently committing on the
french-toast fat is a finding, not a ruler artefact.

14 described meals — 11 dev, 3 holdout — assembled 2026-08-09, the day prompt
v18 made words a first-class input. The photo golden grades what a model reads
off pixels; this one grades what it reads off words, which is a different claim
with a different honest tolerance, and pretending the two are one measurement
is how a confident-looking wrong number ships.

## What the track measures

Prompt v18 ranks the evidence words can carry, and each tier here grades that
promise directly (`weight_source` in `../golden.ts`):

- **stated** — "7 g creatine", "about 180 g" — a fact to transcribe, graded
  ±10% / 2 g. Rounding 13 g of peanut butter to 15 is the failure this tier
  exists to catch, because a stated figure is the one number the person KNOWS.
- **counted** — "3 french toasts", "two eggs", "two glasses of wine" — count ×
  a canonical unit, graded ±30% / 10 g, the spread real units have.
- **typical** — "big bowl", "small bowl", "a slice" — the weakest evidence
  there is. Graded as a range (`weight_tolerance_g` is the half-width), and
  the case is really asking whether the size word moved the number at all:
  TXT_009 fails a model whose "small bowl" and "big glass" both come back as
  the same default serving.

Three checks only a described meal can be asked, all in `../score-text.ts`:

- **No furnishing.** A described meal has no background to inspect, so the
  drink or side the person never mentioned is invention. `forbidden_groups`
  lists what a furnisher would add, and any of them gates.
- **No photograph, nothing skipped.** `other_meals_visible` must be false.
- **Fork quality.** `expected_forks` are the pairs the words genuinely cannot
  settle — "french toast" fried in butter or oil, "meat curry" red or white.
  A good answer commits to one and names the rival in `alternatives`, which is
  what the client renders as its one tappable question; silently committing
  has hidden a decision the person should have been offered, and it gates.
  The mirror case is deliberate too: TXT_008 *names* the butter, and a fork
  there would be asking a question the person already answered. (Not gated in
  v1 — reported through precision — because a spurious fork costs a tap while
  a hidden one costs a wrong score.)

`hidden: true` on the text track means "not in the words": the chashu a ramen
usually carries, the oil a soup was cooked in. Same mechanics as the photo
track — not required of a plain run, never counted spurious when reported with
the golden's blessing — because a model may reasonably infer them from the
dish name and must not be punished either way. The `expected_forks` mechanism
is how the important subset of these (the score-moving fats) gets required.

## Provenance, honestly

The descriptions are **authored** — written the way a person types into the
chat thread — and the ranges are annotated from reference portions, not from
plates that were weighed. TXT_002 derives from IMG_3152, a real logged meal
whose weights were annotated against the photograph; its `derived_from` says
so. This is the dataset's known weakness: an authored description can never
surprise the way a real one does, and the fix is production typed logs with
human corrections joining the set as they accumulate. Treat v1's numbers as a
baseline instrument, not a verdict.

Two live probes through the dev worker (gemini-3.6-flash, prompt v18,
2026-08-09) shaped the tiers and are the founding evidence that the track is
measuring behaviour that exists: "leftover lentil soup, big bowl" returned
220 g lentils + 150 g vegetables + 10 g inferred oil with a butter rival —
inside TXT_001's ranges, with exactly TXT_001's hidden-fat shape — and the
TXT_002 description returned 3×50 g eggs, 7 g creatine transcribed exactly,
and a butter/olive-oil fork on the frying fat.

## Running

```bash
pnpm eval:text          # dev cases, candidate models, 3 runs each
pnpm eval:text:score    # score the latest text artefact
```

Holdout cases (TXT_101–103) are excluded from ordinary runs for the same
reason as the photo holdout: they answer whether a prompt generalises, and
that answer is spent the moment you iterate against their failures.

## Traps

Text-mode failure categories, extending the photo list deliberately:

- `text_stated_figure` — a stated number transcribed wrongly or rounded
- `text_counted_units` — a count not multiplied through a sane unit weight
- `text_size_word` — a vessel/size word that didn't move the number
- `text_furnishing` — food added that the words never mentioned
- `text_fork_expected` — a genuine ambiguity silently committed
- `text_stated_fat_no_fork` — the person named the fat; asking again is noise
- `text_vague_group` — wording that genuinely underdetermines the group
- `text_named_product` — weight from what a product name means
- `text_quoted_label` — panel figures relayed in words
- `text_fraction` — "half a" applied, not ignored
- `panel_from_memory` — figures for a recognised product the words never gave
