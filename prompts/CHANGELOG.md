# Prompt changelog

Newest first. Every entry names the failure the change is meant to fix, so a
version that does not fix anything is visibly a version that does not fix
anything.

v9 through v16 shipped without entries. That is a gap in this file, not a run of
versions that changed nothing.


## revision-v6-2026-08-16

- **An added row's alternatives now carry `grams`.** The recognition contract
  had weighed every rival since alternatives were priced — a tuna sub priced at
  the turkey sub's weight is a number that looks chosen and is not — but the
  correction contract still asked for label and `per_100g` only, and the app's
  stored `FoodAlternative` requires a weight. Any correction that added a row
  with rivals therefore failed to decode. One shape for a rival everywhere.

## activity-revision-v1-2026-08-15

The first correction prompt for something that is not food. "That sauna was
thirty minutes, not twenty" needs somewhere to go, and re-running recognition
on the words would throw away whatever else the row said.

- **A delta over four fields.** `label`, `kind`, `duration_minutes`,
  `start_time` — every one nullable, and null means *unchanged*. That is the
  entire editable surface of an activity, because it is the entire stored one.
- **`unset` is how a field is taken away.** Null already means "leave it", so
  it cannot also mean "remove it"; "actually I don't know how long" names the
  field in `unset` and leaves it null. Both at once is a contract violation on
  both sides.
- **Recorded, not priced — after a fix, too.** No energy field exists in the
  correction schema any more than in recognition, and the prompt closes the
  one hole a schema cannot: an estimate written into `label`.
- Duration and start remain transcription only. Never inferred, in a
  correction as in a recognition.

## meal-v27-2026-08-15

Activities are out of the release, so everything the prompt said about them is
out of the prompt. v26 shipped for part of a day; this is what it should have
been without a feature that was still being designed.

- **The Activities section, the `kind` table, and the duration and start-time
  rules are gone.** So is `entry`: with only meals reachable it narrowed to
  "meal or nothing", which is `dishes` being empty restated, and a
  discriminator that restates the thing it discriminates is a second copy of
  one fact.
- **An empty answer is stated as a real answer.** "If the input describes no
  food at all, return no dishes." That is the whole of the couldn't-read
  signal now, and without the sentence the model assembles a meal out of a
  greeting rather than declining — which is worse than a screen admitting it
  did not understand.
- `activity-revision-v1.md` is deleted with the path that called it. Correcting
  a meal is unchanged: `revision-v5.md` and its seven figures stand.
- Nothing about composition, panels, menu items or the Atwater check moved.
  The eval cases are the same cases, and the version bump is what makes the
  recognition cache re-ask them under the shorter prompt.

## meal-v26-activities-2026-08-15

The same field that logs a meal now logs a sauna, and the composition block
grew two figures. Both were schema changes first, and for about an hour the
deployed prompt contradicted the deployed schema in three places — asked for
"all five" where seven were required, asked for a panel basis that no longer
existed, and stated an Atwater check without the column that makes a beer
pass it. Two tests asserted opposite things about one contract and both
passed. `contract-agreement.test.ts` now holds the prompt and the schema to
the same list.

- **`entry` first, then `dishes`, then `activities`.** The model names what
  the message is — `meal`, `activity`, `both`, or `none` — before it fills
  either list, so a sauna is not forced into `dishes` because that was the
  only array. `none` is new and deliberate: a greeting used to come back as a
  meal of zero dishes, which is a meal worth zero calories that looks logged.
- **An activity is recorded, not priced.** The schema has no energy field for
  one; the prompt says so and closes the hole a schema cannot, an estimate
  written into `label`. `kind` is a closed six-value list for grouping nights
  and is never displayed; the free-text `label` is what a row shows.
  `duration_minutes` and `start_time` are transcribed, never inferred — "a
  quick sauna" is null, "after the gym" is null. The start is a clock time on
  the logged day rather than an instant, because an instant would need "now"
  in the turn and would be cached with the words and replayed tomorrow
  carrying yesterday's date.
- **Seven composition figures, always.** `alcohol` in grams and `caffeine_mg`
  in milligrams join the five, and zero is stated rather than omitted. Ethanol
  is 7 kcal/g and its energy was already inside `kcal`, so with no column for
  it the self-check saw 89% of a lager's energy unaccounted for on every
  drink; the Atwater line now reads `+ alcohol × 7`. Caffeine is composition
  exactly as sodium is, so a filter coffee has some without a label in the
  photograph.
- **`estimated_serving` is gone.** It let an unlabelled coffee carry a
  caffeine *estimate* in the field reserved for *read* figures. With caffeine
  on `per_100g` the panel is transcription and nothing else, and a printed
  `alcohol` (grams only; ABV is not it) is transcribed beside `caffeine`.
- **`revision-v5`** restates the same seven figures and the same Atwater line
  for corrections, so a revised row is priced under the rules the row was
  recognised under.
- The user turn says the message may be "a meal, an activity, both, or
  neither" and no longer says "classify the meal".

## meal-v24-2026-08-12

Grounded recognition made two thirds of v22 dead weight, and one line of it
actively harmful. The prompt is 1624 tokens down to 1285.

- **`brand` and `market` are gone as fields.** They existed to feed a lookup
  that fetched brands' own pages; search does the same job inside the
  recognition call, so both fields lost their only consumer. The instruction to
  write the brand in Latin script went with them — it was there to match a web
  domain, which is our implementation leaking into a prompt.
- **The branded rule moved into `Dishes`, ahead of the decomposition bullet it
  contradicts.** v22 said to report a branded dish "exactly as you would with no
  brand on it", which told the model to rebuild a Subway sandwich from bread,
  meat, cheese and sauce: three runs of one input returned 697, 897 and 665 kcal
  against a published 698. One row is now the rule, and it is stated before the
  rule that would otherwise override it.
- **The composition-table bullet merged into the as-eaten bullet.** They
  contradicted each other — tables publish unsalted preparations, which is the
  82%-low canteen bibimbap this repo already fixed once — and stating both in
  order left the model to choose.
- **A food you cannot price is looked up, not approximated.** The old
  instruction to name the closest food you do know predates search.
- **The closing restatement is gone.** It repeated three rules already stated,
  and a restatement is how a contradiction gets in unnoticed.

## meal-v22-2026-08-12

A branded food's figures are published by whoever sells it, and until now the
app estimated them instead. `NutrientSource.published` and `SourceRef` have
existed since v21 with nothing able to write them; what was missing was the
question, not the storage.

- **A dish may now name its `brand` and its `market`.** Both nullable, and both
  described as evidence rather than as guesses: a brand is a named chain's named
  product, and a market is a country the input actually shows — printed
  language, a currency, a place the person names. The market field is the whole
  of the JP-versus-US Big Mac problem, and the prompt refuses the one
  substitution that would look right and be wrong: inferring a country from the
  language of the answer.
- **Naming a brand changes nothing else.** The same ingredients, the same
  weights, the same `per_100g`. The brand licenses a *lookup* — two grounded
  calls in the Worker, against the brand's own site — and the prompt says
  explicitly that it does not license figures from memory of a product, which is
  the failure mode it would otherwise invite.

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
