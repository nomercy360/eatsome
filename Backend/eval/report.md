# Eval report

Configuration `meal-v11-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v5-2026-08-06`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

10 outputs over 46 cases.

Excluded, because they were produced under a different configuration: `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|high|plain`, `meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gemini-3.6-flash | candidate | 4/6 | 91% | 100% | 88% | 5/12 | 0% | 0 | 0 | $0.072 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

None — every case agreed with itself across repeats.

## Why cases failed


**gemini-3.6-flash**: missed 2, grouped 1

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**gemini-3.6-flash**

- potato_taxonomy — 2
- nuggets_primary_is_meat — 2
- sauces_missed — 2
- processed_vs_red — 2
- all_limits_no_targets — 2
- caffeine_in_bottled_tea — 2
- homemade_vs_commercial_pastry — 1
- piece_in_a_shared_bowl_is_its_own_dish — 1
