# eatsome eval dataset v3

46 photos + golden annotations, assembled 2026-08-05 from real logged meals and
re-annotated 2026-08-07 in absolute grams — the same quantity question the app
asks from prompt v17 on. v2's quantity was the `count × size × portion` ladder;
scoring a weighing prompt against it graded everything at half-serving
resolution, which is exactly the blur the grams switch removed from the app.

## Structure

- `photos/` — original images, filename = case id
- `golden/<id>.json` — expected recognition output per photo

## Golden schema

Types live in `../golden.ts`; this is the shape in prose.

- `dishes[]` — one entry per named thing on the tray. `name`, `count`
  (servings present — a label on the weights, never a multiplier), optional
  `panel` (figures printed on packaging), `ingredients[]`.
- `ingredients[]` — `name`, `group`, optional `alternatives` (rivals the
  dataset accepts as right answers), `weight_g`, `weight_source`, `flags`,
  `hidden` (not visible on the photo — reachable only via user note / saved
  recipe).

  `protein_g` was **removed** on 2026-08-07, not emptied. It held an
  annotator's rough figure written per serving under the retired ladder, and
  once quantity was re-annotated in grams it no longer matched its own
  `weight_g`: 14 of 36 values implied an impossible density, chicken schnitzel
  at 3.4 g per 100 g. Grading the protein table against it would have baked the
  ladder back in through a field that looked like ground truth. Protein has its
  own track in `../labelled.json` — meals whose figure was printed on a board
  or a package — scored by `pnpm eval:nutrients`.
- `weight_g` — edible weight, ABSOLUTE: everything of that ingredient present,
  across every serving in the photograph. Matches the app's definition, so
  golden and model compare with no conversion.
- `weight_source` — where the number came from, in descending order of trust:
  - `label` — printed on the package (net weight, panel). A measurement;
    graded tight (±10% / 10 g).
  - `annotated` — the annotator's reading of the photograph against references
    in frame. An estimate; graded ±40% / 20 g.
  - `ladder` — mechanically derived from the retired v2 size annotation,
    `count × size × portion × serving-grams`. Scaffolding, not a reading of
    the photo; graded at the ladder's own resolution (±60% / 30 g).
    `pnpm eval:coverage` counts these — they are the outstanding hand-pass
    worklist. As of 2026-08-07 there are none: 174 annotated, 6 label.
- `meal_status` — `eaten` | `ate_part` | `shared_plate` | `not_yet_eaten` |
  `not_a_meal`
- `user_note` — a line the person typed, sent on every track. Never the
  hidden-item note (that one is generated from `hidden` flags for `--notes`
  runs).
- `traps[]` — failure categories for classifying diffs. Do not invent new
  categories; extend the list deliberately.

## Annotation rules for weights

- Weigh what is edible: no bones, shells, rind, pits, or snail shells.
- The nearest place setting only, unless the case's `user_note` says the whole
  table is theirs — then the table at served sizes.
- A sealed package present at the meal weighs what it holds (the kimbap is the
  label's 208 g); a bottle being poured from is scored as the pour, because
  logging a 750 ml bottle for one glass is the `bottle_vs_glass_portion` trap.
- Never fill `weight_g` by running a model over the photo and pasting its
  answer. That makes the golden the model's own reading, and every later
  prompt gets graded on agreement with that model's biases instead of with
  the food.

## Taxonomy notes

The dataset speaks a richer vocabulary than the app on purpose (`potatoes`,
`sauce`, flags, meal statuses); `../taxonomy.ts` declares every gap. A gap is
reported, never scored as model error.

## Metrics (deterministic, no LLM judge needed)

- group recall / precision vs golden (set comparison on `group`, honouring the
  golden's `alternatives`)
- weight match: grams vs grams, summed per group, tolerance by `weight_source`
- dish structure match (grouping, not names) and count match on counted dishes
- panel transcription: wrong or invented figures on labelled items
- hidden-item recall only when the note is provided (separate track)
- nutrients: not scored here. See `../labelled.json` and `pnpm eval:nutrients`.

## Known trap census

foreign_tray_bleed, sauce_missed, hidden_ingredients_home_cooking,
potato_taxonomy, refined_grain_dedup, fruit_in_dessert_not_fruit,
processed_vs_red, white_vs_red_meat, plate_vs_meal, bottle_vs_glass_portion,
homemade_vs_commercial_pastry, zero_alcohol_beer, korean_ocr, japanese_ocr_panel,
russian_ocr, package_mode, per_unit_vs_per_100g, duplicate_meal_across_photos,
juice_not_fruit, smoothie_vs_fruit_vs_juice, raw_vs_cooked, prep_photo_not_meal,
opaque_packaging_no_hallucination, dessert_components_not_separate,
chechil_looks_like_noodles, prosciutto_processed_not_red, two_person_split.

Control case: IMG_3169 (dragon fruit). Any error there = pipeline broken —
including its weight: half a dragon fruit is ~150 g of flesh, and the ladder's
derivation said 30 g, which is the entire argument for grams in one number.
Behavioral cases (correct action, not just correct groups):
IMG_3176 raw steaks -> must refuse to log as eaten;
IMG_3177 wraps -> must flag unknown filling, not hallucinate;
IMG_3184+IMG_3185 -> same yogurt on two photos, must not double-count.
