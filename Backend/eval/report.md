# Eval report

Configuration `meal-v16-2026-08-07|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v6-2026-08-06`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

138 outputs over 46 cases.

Excluded, because they were produced under a different configuration: `meal-v11-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|legacy-input|default|plain`, `meal-v15-2026-08-06|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v16-2026-08-07|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|high|plain`, `meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gemini-3.6-flash | candidate | 30/46 | 92% | 89% | 62% | 19/60 | 16% | 0 | 0 | $0.909 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **gemini-3.6-flash**: IMG_3172, IMG_3177, TG_95674, TG_95683, TG_95751, TG_95782, TG_95802

## Why cases failed


**gemini-3.6-flash**: no 33, missed 13

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**gemini-3.6-flash**

- sauce_missed — 10
- homemade_vs_commercial_pastry — 6
- legumes_recall — 6
- paratha_hidden_fat — 6
- potato_taxonomy — 5
- avocado_taxonomy_healthy_fats — 4
- seafood_dedup — 4
- piece_in_a_shared_bowl_is_its_own_dish — 3
- dairy_dedup — 3
- butter_present — 3
- caffeine_in_coffee — 3
- fruit_in_dessert_not_fruit — 3
