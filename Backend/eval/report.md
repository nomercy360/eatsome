# Eval report

Configuration `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v4-2026-08-05`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

38 outputs over 44 cases.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen3-vl-235b | candidate | 12/38 | 76% | 74% | 45% | 15/35 | 16% | 15 | 0 | $0.042 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

None — every case agreed with itself across repeats.

## Why cases failed


**qwen3-vl-235b**: missed 19, duplicated 12

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**qwen3-vl-235b**

- refined_grain_dedup — 6
- sauce_missed — 5
- seafood_dedup — 4
- butter_present — 3
- missed_soup — 3
- foreign_meal_bleed — 3
- package_mode — 3
- avocado_taxonomy_healthy_fats — 2
- dairy_dedup — 2
- foreign_tray_bleed — 2
- white_vs_red_meat — 2
- jam_is_sweets_not_fruit — 2
