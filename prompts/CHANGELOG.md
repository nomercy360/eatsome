# Prompt changelog

Newest first. Every entry names the failure the change is meant to fix, so a
version that does not fix anything is visibly a version that does not fix
anything.

v9 through v16 shipped without entries. That is a gap in this file, not a run of
versions that changed nothing.

## meal-v18-2026-08-09

The meal may now arrive as words — typed or dictated in the chat-first logging
redesign — as a photograph, or as both, and v17 could not say what to do with
words: every rule was written as if an image existed ("estimate weight against
what is in the frame", "if you cannot read the panel, null").

- **The opening no longer promises a photograph.** A new block names the three
  arrivals and what each one licenses. Words alone are the entire input, and
  the model is told not to furnish the meal — no implied drink, side or sauce,
  because a described meal has no background to inspect. Words plus photograph
  ranks the words above the model's own reading, which is the note rule
  generalised. `other_meals_visible` is false when nothing could be skipped.
- **Weight without a photograph is estimation, and the prompt says so.** The
  design's claim has always been that a weight is observation — the model reads
  the photograph — while calories are inference. A weight from "big bowl" is a
  weaker claim than a weight from pixels, and pretending otherwise would be the
  exact confident-looking-wrong-number failure this file exists to prevent. So
  the words rank by what they actually say: a stated figure is transcribed
  ("7 g of creatine" is 7), a count of a named thing weighs that many of it
  ("3 french toasts"), and a vessel or size word is named as the weakest
  evidence — a typical serving scaled by the person's own word, with no more
  precision than the words contain. Weight stays permitted because a
  description states an amount of food; calories stay banned because no
  description of a plate states them.
- **A quoted label is a panel; a remembered one is not.** "The label says 12 g
  of protein per 100 g" is transcription at one remove and lands in `panel`
  with `basis` from the person's words. Figures from memory of a recognised
  product stay banned in both modes, and a named product's usual *size* is
  carved out explicitly — "a can of Coke" weighs what a can holds, because that
  is what the name means, not what a label prints.
- **Evidence rules gained their words-mode half.** Cooking fat: a dish whose
  name says how it was cooked carries its fat (fried rice was fried in
  something). `pastry`: the person naming a bought product now counts as the
  manufactured-item evidence a wrapper used to be.

Bumping the version invalidates the recognition cache and moves every eval row,
as any prompt change does. Not graded yet against the golden set.

## meal-v17-2026-08-07

One quantity. v16 asked for `grams` and for `portion` and `size` alongside it,
and the two answers had to be reconciled somewhere — which meant every reader,
human or machine, had to know that grams win.

- **The prompt contradicted itself.** v16 asked for a weight on every ingredient
  and then, eleven lines later in the panel section, said "Report food GROUPS
  and coarse PORTIONS only. Never estimate calories, grams, or macronutrients".
  Both lines shipped. The second is a v10-era rule that survived the rewrite,
  and it sat in exactly the section a packaged item exercises.
- **`portion` and `size` are gone from the contract.** Grams are absolute and
  nothing multiplies them, so a coarse second opinion had no consumer:
  `effectiveServings` already preferred grams, which made a `portion` the model
  spent tokens on unreadable and a `size` chip in the UI inert. Asking for one
  number means it cannot disagree with another.
- **The panel rule now says what it means.** Calories, fat and carbohydrate are
  still read off a label or not reported; `grams` is named as the exception,
  because a weight is something the photograph shows.

Not graded yet. v16's numbers were measured against the eval schema, which
carries grams; the production Gemini schema never did — see the note in
`Backend/worker/ai/gemini.ts`.

## meal-v8-2026-08-05

Three changes, two of them fixing rules that could not be obeyed. Still not the
app's prompt: v5 ships, and `scripts/sync-prompt.mjs` is pinned to it.

- **Butter was routed to a group the schema does not have.** v7 said to report
  "butter or cream cheese on bread" as `sauce` and to put `` `butter` `` in
  `alternatives`. `butter` is the *app's* spelling; the eval enum only has
  `butter_margarine_cream`, and `alternatives` is a strict enum — so a model
  obeying that line literally could not emit the value. Meanwhile the golden set
  has always grouped plain butter as `butter_margarine_cream` (IMG_3140,
  IMG_3152, IMG_3173) and cream cheese as `dairy` (IMG_3167), so every butter
  row cost recall and precision at once. v8 keeps `sauce` for compound sauces
  and says plainly that a single named fat or dairy served plain is that food.
  A new assertion in `parity.test.ts` fails on any group the prompt names and
  the schema lacks — it flags `butter` in v7 and is clean on v8.
- **The bottle-and-glass rule covered one state of three.** v7's prose — "one
  item, measure what is being drunk" — describes the result instead of
  enumerating the cases, which leaves a model that can see two vessels with no
  permission to return zero rows for one of them. `TG_95836` duplicated
  `alcohol` in 3/12 runs on exactly that shape, and `TG_95802` (sealed bottle,
  nothing poured) drew a phantom `alcohol` row from all four models, 12/12. v8
  replaces the sentence with a six-row state table and says outright that zero
  rows is a correct answer. The table is scoped to drinks on purpose: a general
  "sealed means do not log" would collide with the ssamjang sachet in IMG_3171,
  whose `sauce` row is already missed 9/12.
- **No packaging change, deliberately.** `TG_95624` looked like a missing rule
  for see-through packs, but the flag data says otherwise: `opaque_packaging`
  fired in 1 of 12 runs, the other 11 named and decomposed the pack and simply
  read the filling wrong, and gemini got `white_meat` 3/3. That is perception,
  not instruction-following, and a rule would have moved it a couple of points
  while risking the opaque branch that IMG_3177 currently passes 9/12.

Known limit of this version's evidence: the three zero-row states in the table
cannot be gated by `scorer-v3`. A single spurious row never trips the duplicate
gate (`n > max(1, wanted)` is false at n=1) and recall cannot see it, so those
rows are reported-only. `TG_95680` was added as the one drink state that does
gate in all three directions.

## meal-v7-2026-08-05

The first version written from eval evidence rather than from reading photos.
Every rule below names the cases that failed under `meal-v6`, scored by
`scorer-v3-2026-08-05`. Not yet the app's prompt: v5 still ships.

- **Same-group rows within one dish.** gemini-3.6-flash lost four cases at 100%
  recall — it saw everything and emitted the parts twice: `alcohol` for a
  champagne bottle and the glass poured from it (IMG_3174), `fish` for prawns,
  squid and mussels off one seafood plate (IMG_3181), `sweets` for a waffle and
  its toppings (IMG_3180), `vegetables` for rocket and pickled peppers on one
  pizza (IMG_3182). Added a merge rule that is strictly within a group, so the
  cross-group decomposition above it still stands. It cannot break the seven
  goldens that legitimately repeat a group — every one of those repeats across
  distinct dishes, and merging rows can only lower a row count, which the excess
  check measures against the golden's own repeats.
- **A baked sweet reported as its parts.** IMG_3165, two homemade cherry tarts:
  one run answered `refined_grain` crust plus `fruit` filling and no `sweets` at
  all, 0% recall. Narrowed deliberately to baked sweets — fruit *added to* a dish
  that is not a dessert keeps its row, or IMG_3152, IMG_3170 and IMG_3173 would
  all start losing their banana and their honey.
- **Labelled packages read as opaque ones.** IMG_3171, a kimbap package held up
  in a convenience store: the wrapper carries a product photograph of the
  cross-section and states the enclosed ssamjang, and two of three runs answered
  a single `other` item anyway. v6 only ever described the opaque branch. The
  packaged food keeps `package` as its measure and the components read off the
  label take their own, which is how the golden is labelled.
- **Wrapped items dropped entirely.** IMG_3177, wraps in opaque paper: two of
  three runs fell back to `other` rather than reporting the bread they could
  plainly see. `filling_unknown` existed in the schema and in v6's flag list, but
  nothing said the wrapper is still evidence of a flatbread.
- **Solids submerged in sauce.** IMG_3178, sea bream in tomato sauce: the baby
  potatoes sitting in the sauce were missed in all three runs. The olives were
  not — that half of the diagnosis was wrong, and the rule says potatoes and
  beans rather than restating the olives.

Two things this version deliberately does not change. The nearest-place-setting
rule stays exactly as it was: it is right for the common photograph and its rare
error is the cheap direction, and the expensive branch is reached through the
user line instead. And the tomato sauce in IMG_3178 is still a disagreement
between the prompt, which routes cooked tomato-and-onion to `sofrito`, and the
golden, which calls it `vegetables` — a labelling decision, not a prompt bug.

## meal-v5-2026-08-05

No rule changes. v4's text lifted out of the Swift string literal into
`meal-v5.md`, which the app, the proxy and the eval harness now all read.
Whitespace normalised in the process, which is why it gets a version rather than
being called the same prompt: the bytes differ, and a recognition cached under
v4 was produced by different bytes.

## meal-v4-2026-08-05

- **Sauces were skipped entirely.** A kebab with visible garlic and chilli sauce
  produced no sauce item, and dressings are the main carrier of fat in street
  food. Added an explicit checklist plus routing: mayonnaise and cream-based
  dressings as `butter`, oil-based as `olive_oil`, cooked tomato-and-onion as
  `sofrito`, yoghurt sauces as `dairy`.
- **Avocado came back as `fruit` with `vegetables` as the alternative** — both
  wrong, and scoring it as fruit credits a serving never eaten while hiding the
  fat. Added `healthy_fats` and a rule sending avocado, olives, seeds and tahini
  there.
- **Hedging in the label**: "sliced melon or pineapple". The label now names one
  food and forks go in `alternatives`.
- **`pastry` offered for home cooking.** It now needs visible evidence of a
  manufactured item.
- **Alcohol-free beer** scored as nothing by luck rather than by rule.
- **The note slot**: what the photograph cannot show, treated as ground truth
  about ingredients, plus the exception that lifts the closest-tray restriction
  when the person says the rest is theirs.

## meal-v3-2026-08-05

- **Self-reported confidence was uncalibrated** — the same 0.56 on white rice and
  on unidentifiable meat, which made the low-confidence threshold flag every row
  and mean nothing. Replaced with `alternatives`: a shortlist of rival groups,
  empty when the group is obvious.
- **`group` was being left empty** for the user to fill in, which is the opposite
  of recognition. It is now always the model's best answer.

## meal-v2-2026-08-04

- Multiple trays in frame were merged into one meal. Added the closest-tray rule
  and `other_meals_visible`.
- Soups and side bowls were read as background. Added the rule that decomposes
  them — miso soup contains legumes.
