# Eval report

Configuration `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v4-2026-08-05`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

38 outputs over 44 cases.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-fable-5 | ceiling | 32/38 | 98% | 91% | 62% | 20/35 | 18% | 7 | 0 | $2.864 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

None — every case agreed with itself across repeats.

## Why cases failed


**claude-fable-5**: duplicated 5, missed 1

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**claude-fable-5**

- sauce_missed — 4
- refined_grain_dedup — 3
- foreign_meal_bleed — 1
- zero_alcohol_beer — 1
- white_vs_red_meat — 1
- user_line_all_mine — 1
- table_not_my_share — 1
- schnitzel_primary_is_meat — 1
- alcohol_recall — 1
- transparent_window_readable — 1
- package_mode — 1
- korean_ocr — 1
