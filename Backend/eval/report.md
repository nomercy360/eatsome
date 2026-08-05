# Eval report

Configuration `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|default|plain`.
336 outputs over 28 cases.

Excluded, because they were produced under a different configuration: `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|high|plain`. Select one with `--config`.

## Models

Gates: group recall, and on a note run the hidden items the note named. Reported but not gated: precision, counts, meal_status and excess rows — a spurious item is one tap from deletion, scoring caps repeated groups anyway, and 8-13% meal_status agreement across four independent models says the label is unsettled rather than the models.

| model | tier | pass | recall | precision | measure | counts | meal_status | excess | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 11/28 | 76% | 74% | 41% | 55/96 | 12% | 37 | 0 | $0.016 |
| gpt-5.6-luna | candidate | 9/28 | 73% | 76% | 61% | 39/96 | 13% | 19 | 0 | $0.069 |
| gemini-3.6-flash | candidate | 17/28 | 87% | 88% | 73% | 71/96 | 10% | 6 | 0 | $0.387 |
| claude-haiku-4.5 | candidate | 9/28 | 72% | 71% | 51% | 29/96 | 8% | 24 | 0 | $0.512 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **qwen-3.7-flash**: IMG_3140, IMG_3141, IMG_3170, IMG_3173
- **claude-haiku-4.5**: IMG_3133, IMG_3140, IMG_3179
- **gpt-5.6-luna**: IMG_3128, IMG_3133, IMG_3135, IMG_3170, IMG_3173, IMG_3179, IMG_3182
- **gemini-3.6-flash**: IMG_3133, IMG_3165, IMG_3174, IMG_3177, IMG_3180, IMG_3181, IMG_3182

## Why cases failed


**qwen-3.7-flash**: missed 33, duplicated 29

**claude-haiku-4.5**: missed 47, duplicated 18

**gpt-5.6-luna**: missed 37, duplicated 16

**gemini-3.6-flash**: missed 16, duplicated 6

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**qwen-3.7-flash**

- dairy_dedup — 10
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- white_vs_red_meat — 5
- sauce_missed — 5
- potato_taxonomy — 3
- nuggets_primary_is_meat — 3
- refined_grain_dedup — 3
- sauces_missed — 3
- processed_vs_red — 3
- all_limits_no_targets — 3
- foreign_tray_bleed — 3

**claude-haiku-4.5**

- dairy_dedup — 10
- foreign_tray_bleed — 6
- missed_soup — 6
- white_vs_red_meat — 6
- homemade_vs_commercial_pastry — 6
- sauce_missed — 6
- bottle_vs_glass_portion — 6
- refined_grain_dedup — 5
- vegetable_dedup — 3
- foreign_meal_bleed — 3
- zero_alcohol_beer — 3
- hidden_ingredients_home_cooking — 3

**gpt-5.6-luna**

- dairy_dedup — 10
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- refined_grain_dedup — 4
- plate_vs_meal — 4
- table_vs_my_share — 4
- sauce_missed — 4
- avocado_taxonomy_healthy_fats — 3
- butter_present — 3
- fruit_in_dessert_not_fruit — 3
- hidden_ingredients_home_cooking — 3
- commercial_pastry_forbidden_for_homemade — 3

**gemini-3.6-flash**

- table_vs_my_share — 5
- sauce_missed — 5
- refined_grain_dedup — 4
- two_person_meal — 3
- hidden_spread_under_toppings — 3
- latte_is_dairy — 3
- dairy_dedup — 3
- schnitzel_primary_is_meat — 3
- alcohol_recall — 3
- shelf_photo_not_eaten — 3
- korean_ocr — 3
- package_mode — 3
