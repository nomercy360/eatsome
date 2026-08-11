# Eval report

Configuration `meal-v19-2026-08-10|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|low|plain`, scored by `scorer-v8-2026-08-09`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

276 outputs over 46 cases.

Excluded, because they were produced under a different configuration: `meal-v11-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|legacy-input|default|plain`, `meal-v15-2026-08-06|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v16-2026-08-07|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v16-2026-08-07|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v17-2026-08-07|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v18-2026-08-09|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v18-2026-08-09|eval-schema-v5-2026-08-07|legacy-input|default|text`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|high|plain`, `meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gemini-3.6-flash | candidate | 31/46 | 93% | 84% | 81% | 13/60 | 15% | 0 | 0 | $1.044 |
| muse-spark-1.2 | candidate | 12/46 | 70% | 68% | 70% | 20/60 | 62% | 0 | 0 | $1.804 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **muse-spark-1.2**: IMG_3128, IMG_3135, IMG_3141, IMG_3168, IMG_3177, IMG_3183, IMG_3184, TG_95604, TG_95625, TG_95647, TG_95716, TG_95792
- **gemini-3.6-flash**: IMG_3177, TG_95683, TG_95716, TG_95751, TG_95838

## Why cases failed


**muse-spark-1.2**: missed 71, no 59

**gemini-3.6-flash**: no 35, missed 15

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**muse-spark-1.2**

- sauce_missed — 15
- potato_taxonomy — 12
- legumes_recall — 9
- foreign_meal_bleed — 8
- jam_is_sweets_not_fruit — 8
- seafood_dedup — 7
- fruit_dedup — 7
- missed_soup — 6
- homemade_vs_commercial_pastry — 6
- paratha_hidden_fat — 6
- bottle_vs_glass_portion — 6
- avocado_taxonomy_healthy_fats — 6

**gemini-3.6-flash**

- sauce_missed — 8
- oversized_portion_default — 6
- legumes_recall — 6
- paratha_hidden_fat — 6
- avocado_taxonomy_healthy_fats — 5
- seafood_dedup — 5
- fruit_dedup — 4
- plate_vs_meal — 3
- count_the_countable_fruit — 3
- homemade_vs_commercial_pastry — 3
- piece_in_a_shared_bowl_is_its_own_dish — 3
- dairy_dedup — 3
