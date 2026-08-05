# Eval report

Configuration `meal-v8-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`, scored by `scorer-v4-2026-08-05` against `2026-08-05-12-46-59_meal-v7-2026-08-05.jsonl` (`meal-v7-2026-08-05|eval-schema-v2-2026-08-05|jpeg-1024-q82-v1|default|plain`).
Numbers from a different scorer version are not comparable with these — the ruler is versioned for the same reason the prompt is.

456 outputs over 44 cases.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 13/38 | 76% | 79% | 38% | 62/105 | 25% | 35 | 0 | $0.018 |
| gpt-5.6-luna | candidate | 22/38 | 83% | 86% | 58% | 56/105 | 16% | 14 | 0 | $0.115 |
| gemini-3.6-flash | candidate | 31/38 | 91% | 94% | 67% | 79/105 | 15% | 2 | 0 | $0.658 |
| claude-haiku-4.5 | candidate | 12/38 | 79% | 78% | 51% | 41/103 | 25% | 35 | 0 | $0.729 |

## Flips

- **qwen-3.7-flash** IMG_3168: pass→fail (user_line_all_mine, table_not_my_share, schnitzel_primary_is_meat, alcohol_recall, sauce_missed, refined_grain_dedup)
- **qwen-3.7-flash** IMG_3184: fail→pass (missed_soup, breading_refined_dedup, sealed_package_eaten_or_not, foreign_tray_bleed, duplicate_meal_across_photos)
- **gpt-5.6-luna** IMG_3133: pass→fail (potato_taxonomy, nuggets_primary_is_meat, refined_grain_dedup, sauces_missed, processed_vs_red, all_limits_no_targets)
- **gpt-5.6-luna** IMG_3137: fail→pass (dairy_dedup, homemade_vs_commercial_pastry)
- **gpt-5.6-luna** IMG_3140: fail→pass (avocado_taxonomy_healthy_fats, dairy_dedup, butter_present)
- **gpt-5.6-luna** IMG_3170: fail→pass (honey_missed, milk_vs_plant_milk_ambiguous)
- **gpt-5.6-luna** IMG_3175: pass→fail (juice_not_fruit, no_added_sugar_still_not_fruit, russian_ocr, package_mode)
- **gpt-5.6-luna** IMG_3177: pass→fail (two_person_split, opaque_packaging_no_hallucination, smoothie_vs_fruit_vs_juice)
- **gpt-5.6-luna** IMG_3180: fail→pass (dessert_components_not_separate, sweets_dedup)
- **gpt-5.6-luna** IMG_3184: fail→pass (missed_soup, breading_refined_dedup, sealed_package_eaten_or_not, foreign_tray_bleed, duplicate_meal_across_photos)
- **gpt-5.6-luna** TG_95665: fail→pass (fake_food_object_in_frame, dessert_components_not_separate)
- **gpt-5.6-luna** TG_95709: fail→pass (same_food_two_forms, jam_is_sweets_not_fruit, fruit_dedup, refined_grain_dedup)
- **gpt-5.6-luna** TG_95792: fail→pass (fruit_dedup, platter_one_dish_vs_separate, oversized_portion_default)
- **claude-haiku-4.5** IMG_3137: pass→fail (dairy_dedup, homemade_vs_commercial_pastry)
- **claude-haiku-4.5** IMG_3184: fail→pass (missed_soup, breading_refined_dedup, sealed_package_eaten_or_not, foreign_tray_bleed, duplicate_meal_across_photos)
- **claude-haiku-4.5** TG_95838: pass→fail (bottle_and_glass_differ, fruit_dedup)
- **gemini-3.6-flash** IMG_3133: fail→pass (potato_taxonomy, nuggets_primary_is_meat, refined_grain_dedup, sauces_missed, processed_vs_red, all_limits_no_targets)
- **gemini-3.6-flash** TG_95604: fail→pass (unit_set_merge_and_count, seafood_dedup, butter_present)

## Unstable across repeats

- **qwen-3.7-flash**: IMG_3133, IMG_3137, IMG_3141, IMG_3168, TG_95665, TG_95674, TG_95683
- **gpt-5.6-luna**: IMG_3133, IMG_3173, IMG_3177, TG_95604, TG_95802, TG_95838
- **claude-haiku-4.5**: IMG_3133, IMG_3128, IMG_3137, IMG_3166, IMG_3183, TG_95665, TG_95683, TG_95823, TG_95838
- **gemini-3.6-flash**: TG_95624, TG_95751, TG_95838

## Why cases failed


**qwen-3.7-flash**: missed 47, duplicated 32

**gpt-5.6-luna**: missed 34, duplicated 11

**claude-haiku-4.5**: missed 45, duplicated 31, did 1

**gemini-3.6-flash**: missed 15, duplicated 2

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**qwen-3.7-flash**

- refined_grain_dedup — 13
- sauce_missed — 12
- seafood_dedup — 10
- package_mode — 9
- fruit_in_dessert_not_fruit — 6
- foreign_meal_bleed — 6
- korean_ocr — 6
- bottle_vs_glass_portion — 6
- unit_set_merge_and_count — 6
- white_vs_red_meat — 5
- dessert_components_not_separate — 5
- missed_soup — 4

**gpt-5.6-luna**

- refined_grain_dedup — 15
- seafood_dedup — 10
- package_mode — 9
- sauce_missed — 7
- korean_ocr — 6
- juice_not_fruit — 6
- potato_taxonomy — 5
- jam_is_sweets_not_fruit — 5
- unit_set_merge_and_count — 4
- butter_present — 4
- user_line_all_mine — 3
- table_not_my_share — 3

**claude-haiku-4.5**

- refined_grain_dedup — 17
- sauce_missed — 13
- seafood_dedup — 11
- dairy_dedup — 10
- butter_present — 9
- foreign_meal_bleed — 9
- package_mode — 9
- avocado_taxonomy_healthy_fats — 6
- korean_ocr — 6
- jam_is_sweets_not_fruit — 6
- unit_set_merge_and_count — 6
- dessert_components_not_separate — 5

**gemini-3.6-flash**

- refined_grain_dedup — 11
- seafood_dedup — 5
- sauce_missed — 5
- olives_in_sauce_missed — 3
- potatoes_in_sauce_missed — 3
- shared_bread_bleed — 3
- sauce_as_vegetables_judgment — 3
- assembly_components_not_a_dish — 3
- foreign_meal_bleed — 3
- potato_taxonomy — 3
- missed_soup — 3
- same_food_pan_and_plate — 3
