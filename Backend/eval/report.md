# Eval report

Configuration `meal-v18-2026-08-09|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v8-2026-08-09` against `2026-08-07-01-50-17_meal-v17-2026-08-07.jsonl` (`meal-v17-2026-08-07|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|default|plain`).
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

414 outputs over 46 cases.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gpt-5.6-luna | candidate | 26/46 | 89% | 76% | 56% | 20/60 | 27% | 0 | 0 | $0.189 |
| gemini-3.6-flash | candidate | 32/46 | 93% | 86% | 85% | 13/60 | 26% | 0 | 0 | $1.024 |
| grok-4.5 | candidate | 31/46 | 91% | 74% | 72% | 22/60 | 21% | 0 | 0 | $2.837 |

## Flips

Nothing flipped.


## Unstable across repeats

- **gpt-5.6-luna**: IMG_3133, IMG_3165, IMG_3174, IMG_3177, TG_95624, TG_95674, TG_95683, TG_95695, TG_95709, TG_95782, TG_95802, TG_95838
- **gemini-3.6-flash**: IMG_3165, TG_95782
- **grok-4.5**: IMG_3165, IMG_3179, TG_95647, TG_95665, TG_95802

## Why cases failed


**gpt-5.6-luna**: no 29, missed 25

**gemini-3.6-flash**: no 35, missed 12

**grok-4.5**: no 30, missed 20

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**gpt-5.6-luna**

- sauce_missed — 9
- oversized_portion_default — 6
- fruit_dedup — 6
- bottle_vs_glass_portion — 5
- plate_vs_meal — 4
- korean_ocr — 4
- seafood_dedup — 4
- prosciutto_processed_not_red — 4
- legumes_recall — 4
- count_the_countable_fruit — 3
- potato_taxonomy — 3
- shelf_photo_not_eaten — 3

**gemini-3.6-flash**

- sauce_missed — 11
- oversized_portion_default — 6
- legumes_recall — 6
- paratha_hidden_fat — 6
- fruit_dedup — 6
- plate_vs_meal — 5
- homemade_vs_commercial_pastry — 5
- potato_taxonomy — 5
- count_the_countable_fruit — 3
- piece_in_a_shared_bowl_is_its_own_dish — 3
- avocado_taxonomy_healthy_fats — 3
- dairy_dedup — 3

**grok-4.5**

- sauce_missed — 10
- oversized_portion_default — 6
- legumes_recall — 6
- paratha_hidden_fat — 6
- plate_vs_meal — 4
- homemade_vs_commercial_pastry — 4
- count_the_countable_fruit — 3
- piece_in_a_shared_bowl_is_its_own_dish — 3
- paratha_not_whole_grain — 3
- one_bowl_two_dishes — 3
- shelf_photo_not_eaten — 3
- korean_ocr — 3
