# Eval report

Run `2026-08-05-05-06-39_meal-v6-2026-08-05.jsonl`.
28 cases, 5 models known.

## Models

| model | tier | pass | recall | precision | measure | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 14/28 | 76% | 74% | 50% | 0 | $0.016 |
| claude-haiku-4.5 | candidate | 10/28 | 72% | 71% | 70% | 0 | $0.512 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **qwen-3.7-flash**: IMG_3128, IMG_3141, IMG_3170, IMG_3173, IMG_3179, IMG_3182
- **claude-haiku-4.5**: IMG_3128, IMG_3133, IMG_3140, IMG_3141, IMG_3179, IMG_3184

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
