# Eval report

Configuration `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v4-2026-08-05`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

38 outputs over 44 cases.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gpt-5.6-sol | candidate | 25/38 | 83% | 85% | 55% | 16/35 | 16% | 9 | 0 | $1.171 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

None — every case agreed with itself across repeats.

## Why cases failed


**gpt-5.6-sol**: missed 13, duplicated 5

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**gpt-5.6-sol**

- refined_grain_dedup — 5
- package_mode — 3
- jam_is_sweets_not_fruit — 3
- korean_ocr — 2
- juice_not_fruit — 2
- sauce_missed — 2
- seafood_dedup — 2
- butter_present — 2
- fruit_dedup — 2
- potato_taxonomy — 1
- nuggets_primary_is_meat — 1
- sauces_missed — 1
