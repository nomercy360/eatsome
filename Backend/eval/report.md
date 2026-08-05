# Eval report

Run `2026-08-05-05-06-39_meal-v6-2026-08-05.jsonl`, `2026-08-05-05-11-11_meal-v6-2026-08-05.jsonl`, `2026-08-05-05-13-00_meal-v6-2026-08-05.jsonl`.
28 cases, 5 models known.

## Models

| model | tier | pass | recall | precision | measure | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 14/28 | 76% | 74% | 50% | 0 | $0.016 |
| gpt-5.6-luna | candidate | 13/28 | 73% | 76% | 68% | 0 | $0.069 |
| gemini-3.6-flash | candidate | 21/28 | 87% | 88% | 78% | 0 | $0.387 |
| claude-haiku-4.5 | candidate | 10/28 | 72% | 71% | 70% | 0 | $0.512 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **qwen-3.7-flash**: IMG_3128, IMG_3141, IMG_3170, IMG_3173, IMG_3179, IMG_3182
- **claude-haiku-4.5**: IMG_3128, IMG_3133, IMG_3140, IMG_3141, IMG_3179, IMG_3184
- **gpt-5.6-luna**: IMG_3128, IMG_3133, IMG_3173, IMG_3179
- **gemini-3.6-flash**: IMG_3133, IMG_3165, IMG_3177

## Failures by trap


**qwen-3.7-flash**

- dairy_dedup — 8
- homemade_vs_commercial_pastry — 6
- potato_taxonomy — 3
- nuggets_primary_is_meat — 3
- refined_grain_dedup — 3
- sauces_missed — 3
- processed_vs_red — 3
- all_limits_no_targets — 3
- fruit_in_dessert_not_fruit — 3
- plate_vs_meal — 3
- two_person_meal — 3
- hidden_spread_under_toppings — 3

**claude-haiku-4.5**

- dairy_dedup — 9
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- refined_grain_dedup — 5
- sauce_missed — 5
- foreign_tray_bleed — 4
- missed_soup — 4
- white_vs_red_meat — 4
- hidden_ingredients_home_cooking — 3
- commercial_pastry_forbidden_for_homemade — 3
- milk_dedup_batter_vs_mug — 3
- fruit_in_dessert_not_fruit — 3

**gpt-5.6-luna**

- dairy_dedup — 10
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- refined_grain_dedup — 4
- avocado_taxonomy_healthy_fats — 3
- butter_present — 3
- fruit_in_dessert_not_fruit — 3
- plate_vs_meal — 3
- hidden_ingredients_home_cooking — 3
- commercial_pastry_forbidden_for_homemade — 3
- milk_dedup_batter_vs_mug — 3
- two_person_meal — 3

**gemini-3.6-flash**

- refined_grain_dedup — 4
- two_person_meal — 3
- hidden_spread_under_toppings — 3
- latte_is_dairy — 3
- dairy_dedup — 3
- table_vs_my_share — 3
- schnitzel_primary_is_meat — 3
- alcohol_recall — 3
- sauce_missed — 3
- shelf_photo_not_eaten — 3
- korean_ocr — 3
- package_mode — 3
