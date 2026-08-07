# Eval report

Configuration `meal-v17-2026-08-07|eval-schema-v5-2026-08-07|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v7-2026-08-07`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

552 outputs over 46 cases.

Excluded, because they were produced under a different configuration: `meal-v11-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|legacy-input|default|plain`, `meal-v15-2026-08-06|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v16-2026-08-07|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v16-2026-08-07|eval-schema-v4-2026-08-07|jpeg-1024-q82-v1|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|high|plain`, `meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | control | 2/46 | 91% | 75% | 64% | 17/60 | 25% | 0 | 0 | $0.030 |
| gpt-5.6-luna | candidate | 23/46 | 87% | 75% | 61% | 14/60 | 27% | 0 | 0 | $0.173 |
| gemini-3.6-flash | candidate | 31/46 | 92% | 86% | 81% | 12/60 | 14% | 0 | 0 | $0.888 |
| grok-4.5 | candidate | 31/46 | 91% | 77% | 72% | 19/60 | 15% | 0 | 0 | $2.807 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **gpt-5.6-luna**: IMG_3137, IMG_3165, IMG_3166, IMG_3167, IMG_3173, IMG_3174, IMG_3177, IMG_3181, TG_95625, TG_95624, TG_95683, TG_95695, TG_95782, TG_95802, TG_95838
- **gemini-3.6-flash**: IMG_3165, IMG_3181, TG_95716, TG_95751, TG_95838
- **grok-4.5**: IMG_3140, IMG_3135, IMG_3165, TG_95674

## Why cases failed


**gpt-5.6-luna**: no 35, missed 28

**gemini-3.6-flash**: no 34, missed 12

**grok-4.5**: no 33, missed 22

**qwen-3.7-flash**: no 47, missed 25, mango: 6, bread 6, chana 6, tomato 6, chicken 6, beer: 6, whopper: 3, minced 3, dark 3, kebab 3, french 3, cherry 3, dragon 3, porridge 3, sausages: 3, ssamjang 3, champagne: 3, apple-lime 3, raw 3, sea 3, fried 3, bubble 3, seafood 3, prosciutto 3, karaage: 3, escargots 3, sesame 3, mini 3, hand-roll 3, shrimp 3, burrito 3, oladyi 3, marzipan 3, assorted 3, sweet 3, caesar 3, lager 3, wrap: 2, fruit 1

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**gpt-5.6-luna**

- sauce_missed — 9
- oversized_portion_default — 6
- legumes_recall — 6
- foreign_meal_bleed — 6
- korean_ocr — 5
- prosciutto_processed_not_red — 5
- potato_taxonomy — 5
- plate_vs_meal — 4
- paratha_hidden_fat — 4
- bottle_vs_glass_portion — 4
- cheese_on_eggs_missed — 4
- platter_one_dish_vs_separate — 4

**gemini-3.6-flash**

- sauce_missed — 10
- oversized_portion_default — 6
- legumes_recall — 6
- paratha_hidden_fat — 6
- fruit_dedup — 5
- plate_vs_meal — 4
- homemade_vs_commercial_pastry — 4
- avocado_taxonomy_healthy_fats — 4
- count_the_countable_fruit — 3
- piece_in_a_shared_bowl_is_its_own_dish — 3
- dairy_dedup — 3
- butter_present — 3

**grok-4.5**

- sauce_missed — 12
- legumes_recall — 6
- paratha_hidden_fat — 6
- bottle_vs_glass_portion — 6
- oversized_portion_default — 5
- homemade_vs_commercial_pastry — 5
- plate_vs_meal — 4
- potato_taxonomy — 4
- piece_in_a_shared_bowl_is_its_own_dish — 3
- paratha_not_whole_grain — 3
- one_bowl_two_dishes — 3
- shelf_photo_not_eaten — 3

**qwen-3.7-flash**

- sauce_missed — 21
- foreign_meal_bleed — 15
- potato_taxonomy — 12
- missed_soup — 9
- avocado_taxonomy_healthy_fats — 9
- butter_present — 9
- legumes_recall — 9
- alcohol_recall — 9
- jam_is_sweets_not_fruit — 9
- bottle_vs_glass_portion — 9
- seafood_dedup — 9
- fruit_dedup — 9
