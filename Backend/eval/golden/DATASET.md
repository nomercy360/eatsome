# eatsome eval dataset v2

28 photos + golden annotations. Assembled 2026-08-05 from real logged meals.

## Structure

- `photos/` — original images, filename = case id
- `golden/<id>.json` — expected recognition output per photo

## Golden schema

- `golden[]` — expected items: `name`, `group`, optional `alternatives`,
  `measure` (`count` | `size` | `package`), `count` / `size` / `weight_g`,
  optional `protein_g` (rough, for protein-sum eval), `flags` (`fried`, `breaded`),
  `hidden` (not visible on photo — reachable only via user note / saved recipe)
- `meal_status` — `eaten` | `ate_part` | `shared_plate` | `not_yet_eaten`
- `dedup_note` — expected serving aggregation (N items of one group -> 1 serving + modifier)
- `traps[]` — failure categories for the judge/agent to classify diffs against.
  Do not invent new categories; extend this list deliberately.

## Taxonomy prerequisites (add to config BEFORE running)

Groups referenced here that may not exist yet in the app schema:
`potatoes`, `healthy_fats` (avocado, olives), `sauce`, `plant_milk`,
`juice`, `smoothie`,
flags `fried`/`breaded`/`raw_ingredient`/`added_sugar`/`opaque_packaging`,
measure `package`, meal_status `not_yet_eaten` / `shared_plate` / `not_a_meal`.
Running the eval without these yields schema errors, not model errors.

## Metrics (deterministic, no LLM judge needed)

- group recall / precision vs golden (set comparison on `group`)
- portion exact-match (count or size)
- dedup violations (multiple counted servings of one group in one meal)
- hidden-item recall only when user note is provided (separate track)
- protein MAE on items with `protein_g`

## Known trap census

foreign_tray_bleed, sauce_missed, hidden_ingredients_home_cooking,
potato_taxonomy, refined_grain_dedup, fruit_in_dessert_not_fruit,
processed_vs_red, white_vs_red_meat, plate_vs_meal, bottle_vs_glass_portion,
homemade_vs_commercial_pastry, zero_alcohol_beer, korean_ocr, japanese_ocr_panel,
russian_ocr, package_mode, per_unit_vs_per_100g, duplicate_meal_across_photos,
juice_not_fruit, smoothie_vs_fruit_vs_juice, raw_vs_cooked, prep_photo_not_meal,
opaque_packaging_no_hallucination, dessert_components_not_separate,
chechil_looks_like_noodles, prosciutto_processed_not_red, two_person_split.

Control case: IMG_3169 (dragon fruit). Any error there = pipeline broken.
Behavioral cases (correct action, not just correct groups):
IMG_3176 raw steaks -> must refuse to log as eaten;
IMG_3177 wraps -> must flag unknown filling, not hallucinate;
IMG_3184+IMG_3185 -> same yogurt on two photos, must not double-count.
