# Eval report

Configuration `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|default|plain`.
336 outputs over 28 cases.

Excluded, because they were produced under a different configuration: `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|3000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|4000|plain`, `meal-v6-2026-08-05|eval-schema-v1-2026-08-05|high|plain`. Select one with `--config`.

## Models

Gates are recall, duplicate groups, and — on a note run — the hidden items the note named. Precision, counts and meal_status are reported, not gated: a spurious item is one tap from deletion, and `meal_status` disagreement is as likely to be the label as the model.

| model | tier | pass | recall | precision | measure | counts | meal_status | errors | $ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| qwen-3.7-flash | candidate | 9/28 | 76% | 74% | 41% | 55/96 | 12% | 0 | $0.016 |
| gpt-5.6-luna | candidate | 8/28 | 73% | 76% | 61% | 39/96 | 13% | 0 | $0.069 |
| gemini-3.6-flash | candidate | 11/28 | 87% | 88% | 73% | 71/96 | 10% | 0 | $0.387 |
| claude-haiku-4.5 | candidate | 7/28 | 72% | 71% | 51% | 29/96 | 8% | 0 | $0.512 |

## Flips

No baseline given. Re-run with `--against <earlier.jsonl>` to see movement.


## Unstable across repeats

- **qwen-3.7-flash**: IMG_3140, IMG_3141, IMG_3170, IMG_3173
- **claude-haiku-4.5**: IMG_3133, IMG_3179
- **gpt-5.6-luna**: IMG_3128, IMG_3133, IMG_3170, IMG_3173, IMG_3179, IMG_3182
- **gemini-3.6-flash**: IMG_3133, IMG_3128, IMG_3165, IMG_3174, IMG_3177, IMG_3180, IMG_3181, IMG_3182

## Why cases failed


**qwen-3.7-flash**: duplicated 36, missed 33

**claude-haiku-4.5**: missed 47, duplicated 28

**gpt-5.6-luna**: missed 37, duplicated 24

**gemini-3.6-flash**: duplicated 24, missed 16

## Traps carried by failing cases

A case carries several traps, so these count cases rather than trap violations. Read them as where to look, not as what broke.


**qwen-3.7-flash**

- dairy_dedup — 11
- refined_grain_dedup — 6
- plate_vs_meal — 6
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- white_vs_red_meat — 5
- sauce_missed — 5
- potato_taxonomy — 3
- nuggets_primary_is_meat — 3
- sauces_missed — 3
- processed_vs_red — 3
- all_limits_no_targets — 3

**claude-haiku-4.5**

- dairy_dedup — 11
- refined_grain_dedup — 8
- foreign_tray_bleed — 6
- missed_soup — 6
- white_vs_red_meat — 6
- plate_vs_meal — 6
- homemade_vs_commercial_pastry — 6
- sauce_missed — 6
- bottle_vs_glass_portion — 6
- vegetable_dedup — 3
- fruit_dedup — 3
- oversized_portion_default — 3

**gpt-5.6-luna**

- dairy_dedup — 10
- refined_grain_dedup — 7
- plate_vs_meal — 6
- homemade_vs_commercial_pastry — 6
- bottle_vs_glass_portion — 6
- table_vs_my_share — 4
- sauce_missed — 4
- fruit_dedup — 3
- oversized_portion_default — 3
- avocado_taxonomy_healthy_fats — 3
- butter_present — 3
- fruit_in_dessert_not_fruit — 3

**gemini-3.6-flash**

- dairy_dedup — 12
- refined_grain_dedup — 7
- table_vs_my_share — 5
- sauce_missed — 5
- plate_vs_meal — 4
- homemade_vs_commercial_pastry — 4
- fruit_dedup — 3
- oversized_portion_default — 3
- avocado_taxonomy_healthy_fats — 3
- butter_present — 3
- legumes_recall — 3
- paratha_hidden_fat — 3
