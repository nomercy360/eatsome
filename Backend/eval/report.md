# Eval report

Configuration `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v6-2026-08-06`.
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

275 outputs over 46 cases.

Excluded, because they were produced under a different configuration: `meal-v11-2026-08-06|eval-schema-v3-2026-08-06|jpeg-1024-q82-v1|default|plain`, `meal-v14-2026-08-06|eval-schema-v3-2026-08-06|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|default|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|legacy-input|high|plain`, `meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 2/46 | 89% | 77% | 66% | 5/20 | 17% | 0 | 0 | $0.010 |
| gpt-5.6-luna | candidate | 37/46 | 88% | 79% | 69% | 12/20 | 17% | 0 | 0 | $0.064 |
| gemini-3.6-flash | candidate | 40/46 | 94% | 93% | 82% | 8/20 | 15% | 0 | 0 | $0.329 |
| grok-4.5 | candidate | 37/46 | 90% | 83% | 73% | 10/20 | 13% | 0 | 0 | $0.806 |
| claude-sonnet-5 | ceiling | 37/46 | 92% | 84% | 64% | 8/19 | 18% | 0 | 0 | $1.369 |
| claude-fable-5 | ceiling | 42/45 | 97% | 86% | 72% | 10/20 | 18% | 0 | 0 | $4.520 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

None — every case agreed with itself across repeats.

## Why cases failed


**qwen-3.7-flash**: no 13, missed 9, mango: 2, bread 2, chana 2, chicken 2, beer: 2, kebab 1, whopper: 1, minced 1, dark 1, french 1, porridge 1, ssamjang 1, pink 1, dragon 1, sausages: 1, raw 1, apple-lime 1, champagne: 1, wrap: 1, sea 1, seafood 1, bubble 1, fried 1, escargots 1, prosciutto 1, karaage: 1, mini 1, sesame 1, marzipan 1, shrimp 1, hand-roll 1, burrito 1, oladyi 1, lager 1, caesar 1, assorted 1, sweet 1, tomato 1

**gpt-5.6-luna**: missed 9, no 6

**gemini-3.6-flash**: no 3, missed 3

**grok-4.5**: missed 7, no 6

**claude-sonnet-5**: no 7, missed 2, did 2, ssamjang 1

**claude-fable-5**: missed 2, no 2

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**qwen-3.7-flash**

- sauce_missed — 7
- foreign_meal_bleed — 5
- potato_taxonomy — 4
- missed_soup — 3
- avocado_taxonomy_healthy_fats — 3
- butter_present — 3
- legumes_recall — 3
- alcohol_recall — 3
- jam_is_sweets_not_fruit — 3
- bottle_vs_glass_portion — 3
- seafood_dedup — 3
- fruit_dedup — 3

**gpt-5.6-luna**

- sauce_missed — 2
- foreign_tray_bleed — 1
- missed_soup — 1
- white_vs_red_meat — 1
- missed_drink — 1
- bowl_is_one_dish — 1
- legumes_recall — 1
- paratha_hidden_fat — 1
- paratha_not_whole_grain — 1
- one_bowl_two_dishes — 1
- shelf_photo_not_eaten — 1
- korean_ocr — 1

**gemini-3.6-flash**

- sauce_missed — 2
- chechil_looks_like_noodles — 1
- seafood_dedup — 1
- bottle_vs_glass_portion — 1
- three_heaps_one_plate — 1
- transparent_window_readable — 1
- korean_ocr — 1
- prosciutto_processed_not_red — 1
- juice_not_fruit — 1
- assembly_components_not_a_dish — 1
- foreign_meal_bleed — 1
- potato_taxonomy — 1

**grok-4.5**

- potato_taxonomy — 2
- bottle_vs_glass_portion — 2
- seafood_dedup — 2
- legumes_recall — 1
- paratha_hidden_fat — 1
- paratha_not_whole_grain — 1
- one_bowl_two_dishes — 1
- nuggets_primary_is_meat — 1
- processed_vs_red — 1
- all_limits_no_targets — 1
- caffeine_in_bottled_tea — 1
- closed_box_shows_only_bun_and_patty — 1

**claude-sonnet-5**

- legumes_recall — 3
- avocado_taxonomy_healthy_fats — 2
- caffeine_in_coffee — 2
- paratha_hidden_fat — 2
- foreign_meal_bleed — 2
- dairy_dedup — 1
- butter_present — 1
- paratha_not_whole_grain — 1
- one_bowl_two_dishes — 1
- shelf_photo_not_eaten — 1
- korean_ocr — 1
- sauce_sachet — 1

**claude-fable-5**

- cheese_on_eggs_missed — 1
- rye_whole_vs_refined — 1
- caffeine_in_coffee — 1
- chechil_looks_like_noodles — 1
- seafood_dedup — 1
- bottle_vs_glass_portion — 1
- three_heaps_one_plate — 1
- solids_in_sauce_countable — 1
- legumes_recall — 1
- sauce_missed — 1
- paratha_hidden_fat — 1
- same_meal_as_IMG_3166 — 1
