# Working in this repo

## Build and test

```bash
swift test --package-path Core          # needs Xcode's toolchain
```

Without Xcode installed, `Testing` and `XCTest` are both missing from the bare
Command Line Tools. Set `SHAMAN_TESTING_PACKAGE=1` to pull swift-testing in as a
package instead — `Package.swift` handles the switch:

```bash
SHAMAN_TESTING_PACKAGE=1 swift test --package-path Core
```

The Xcode project is generated, not committed:

```bash
./scripts/bootstrap.sh                  # generate eatsome.xcodeproj with XcodeGen
```

Never hand-edit `eatsome.xcodeproj` — edit `project.yml` and regenerate.

## Where things go

`Core/` is framework-free. It must not import UIKit, AVFoundation, MediaPipe, or
HealthKit. That constraint is what makes the rep counter testable against
synthetic skeletons, and it is worth defending.

Anything that touches a framework goes in `App/`. HealthKit is isolated in
`App/Support/HealthKitBridge.swift`; imported Health data remains read-only.

## Invariants

- **Time is `EpochMillis`, UTC.** No `Date` in any stored type; local time is
  derived at render time.
- **IDs are `UUIDv7.generate()`.** Never `UUID()` for anything persisted.
- **Storage is append-only.** Corrections are `mealRevised` events, not
  mutations. Nothing rewrites a line of `events.jsonl`. New fields on stored
  types must be optional, or every existing line fails to decode and the meal
  silently disappears from the projection.
- **A text correction is a delta, never a re-run.** `MealRefiner` returns a
  `MealRevision` that touches only the rows the model names; hand edits survive.
  It is also the *only* way a quantity is corrected by hand — an `add` and a
  `revise` both carry `grams`. They carried a `Portion` until v17, which could
  not move a weighed row at all: the delta applied, the summary said "1 changed",
  and `effectiveServings` went on reading the weight.
- **Nothing asks a model for a number except a weight.** That rule is
  unchanged and is the one the rest rests on. A model asked how many calories
  are on a plate returns a figure with 30–50% error that is indistinguishable
  from data; a model asked what something weighs is reading the photograph.
  `LunaSessionTests` still fails if the prompt or either schema mentions
  calories.

- **The other four figures are looked up, never estimated.** Energy,
  carbohydrate, fat and sodium are `grams × per 100 g` from a published
  composition row, exactly the arithmetic protein has always used, and they come
  off the *same* source row as the protein figure — see `FoodNutrientTable` and
  `scripts/build-food-table.py`. This replaced a two-year ban on calories in
  August 2026. What lifted the ban was not a change of opinion but the arrival
  of a complete baseline: the objection to totalling a transcribed panel was
  that only packaged food carries one, so the total would be built from the
  packaged fraction of a meal while looking exactly like a total.

- **A total is only allowed when every food group can answer.** That is the
  condition the paragraph above turns on, so it is a test rather than a
  convention: `FoodNutrientTableTests.everyGroupHasARepresentative` requires a
  sourced `GROUP_REPRESENTATIVE` row for all 27 groups but `other`. `other` has
  none on purpose — it is the bucket for food that was not recognised, and a
  figure for it would be invented rather than estimated. Its weight lands in
  `NutrientTotal.unresolvedGrams`, which every screen showing a total must
  surface; a partial total that does not say it is partial is the exact failure
  this whole design is arranged against.

- **Salt is a floor, and no screen may score it against the ceiling.**
  Composition tables publish plain preparations — cooked white rice is 1 mg of
  sodium per 100 g — while the salt in cooked food is added in sauces and
  seasoning that carry no weight on the plate and appear in no ingredient list.
  Measured against a canteen bibimbap that printed 4 g, the derived figure was
  0.7 g: 82% low, and structurally so. `Nutrients.saltGrams` is therefore the
  salt *in the food*, displayed as `≥`, with `DailyTargets.saltCeilingGrams`
  deliberately not shown beside it. A salt reading of "well under" on a 4 g
  lunch would be a confident, complete-looking, wrong number.

- **Protein keeps its own group table, and it does not move.** On a table miss
  protein falls back to `Protein.defaultGramsPerServing` while the other four
  fall back to `FoodNutrientTable.groups`, so the two disagree slightly — cod is
  22.8 g per 100 g against the `fish` row's 22. That seam is deliberate: every
  protein figure in the history was scored against the hand-calibrated table,
  and `pnpm eval:nutrients` measures changes to it. Consistency with a table
  that did not exist when those figures were written is not worth restating
  them.

- **`Nutrition` is the only place any of the five is computed.**
  `Protein.grams` is a thin accessor onto it, not a second implementation. Two
  routes to the same number is how the number starts depending on which screen
  asked.
- **Recognition asks for weight, and for nothing else numeric.** An ingredient
  carries `grams` — the edible weight of it on the plate. Fat, carbohydrate and
  calories are still never requested: a weight is something a photograph shows,
  and those are a food database's answer rather than a model's.

  This replaced a three-step portion ladder in August 2026, on evidence rather
  than taste. Scored against Nutrition5k, whose ingredients were weighed on a
  scale as they went onto the plate, the ladder ran 37% median error against
  grams' 26%, and systematically under-read: ×0.68 on plates over 45 g of
  protein. Grams also express what the ladder could not say at all — `large`
  caps at two servings, so 300 g of beef in a pan had no representation.
- **Weight is the only quantity, and it is required.** `portion` and `size` were
  asked for alongside `grams` from v16 and always lost to it in
  `effectiveServings`, so from v17 neither is in a prompt, a response schema, or
  a control. `grams` is non-nullable in `mealRecognitionItemSchema`, which is the
  point: while a coarse fallback stood behind it, the production Gemini schema
  omitted the field entirely for a month, every answer still parsed, and every
  meal was quietly scored on the ladder grams had replaced. A fallback for a
  required measurement is a way to not notice it is missing.

  Both stored fields survive on `MealItem` and `MealDish` because the log is
  append-only and a meal from before v17 must score the way it scored the day it
  was written. Nothing sets them on a new item.
- **The Gemini response schema is hand-written; everything else is derived.**
  `geminiResponseSchema()` in `Backend/worker/ai/gemini.ts` is the one contract
  not generated from Zod — Gemini rejects `additionalProperties` and spells
  nullable as a flag — and it emits *exactly* the properties it names, dropping
  anything the prompt asks for and it does not declare. That is how v16 shipped
  a weighing prompt that returned no weights. `recognize.test.ts` now compares
  its ingredient fields against `mealRecognitionJsonSchema()`; keep that guard.
- **Grams are absolute, and nothing multiplies them.** An ingredient's `grams`
  is everything of it present, across every serving in the photograph. The dish
  still carries `count`, but as a label and a control: changing it rewrites the
  weights (`MealDish.scaled(toCount:)`) rather than scaling at score time. The
  old `count × size × portion` product is what made one bowl of ramen worth
  126 g of protein — the model called the bowl large and the noodles large, and
  the two compounded. Measured, that structure cost 7 points of median error and
  half again as many gross misses. `MealDish.weighed` is the switch; a meal
  logged before grams keeps the ladder and scores exactly as it always did.
  `flattenDishes` now writes `servings: null` on every row: there is no
  arithmetic left for the server to do.
- **`ServingWeight` converts weight to display servings, and is not a nutrition
  table.** It says how much one serving of a group weighs, nothing about what is
  in it. Its alcohol row is approximate by construction: a drink is defined by
  ethanol rather than volume.
- **A transcribed panel wins figure by figure, not wholesale.** A printed
  number is a fact and beats the table for that nutrient only; a carton printing
  protein and energy but no sodium contributes two read figures and three
  derived ones. Discarding the ingredients over a partial panel, or the panel
  over a missing field, both throw away something true. Everything derived is
  computed on read and never written, so retuning `shaman-config.json` moves
  every estimate in the history and no measurement.

- **Daily references require a complete adult profile.** `NutritionProfile`
  holds age, published sex-reference equation, height, weight, optional body
  fat, activity, and goal. HealthKit values win at the app boundary and manual
  values fill gaps; neither is part of a meal event. `DailyTargets` uses the
  2023 adult DRI equations, retains carbohydrate/fat/protein AMDR ranges, and
  shows a goal adjustment separately from maintenance. Missing inputs return
  `nil`, never an imaginary default. Body fat supplies approximate lean mass and
  does not enter the official energy equation.
- **A meal is dishes; a dish is ingredients.** `count` is how many servings of
  the dish; `size` is a stored leftover that only multiplies on a meal described
  in portions, which is every meal logged before August 2026 and everything added
  by hand. `MealEntry` stores the dishes and the flat list both, and
  `MealDish.flattened()` is the only thing that writes the flat list; a build
  from before dishes scores an old meal and a new one alike from it.
- **Quantity is shown, not picked.** The dish sheet (`2d`) offers a count
  stepper and nothing else; the ingredient sheet shows a weight and does not
  edit it. Both offered portion chips until v17, and on a weighed row the chips
  changed no number while looking exactly like a control that did. A wrong weight
  is corrected in words on the fix screen, which is what `MealRefiner` is for.
- **Items are what was seen; `MealEntry.servings(of:)` is what counts.** A meal
  contributes at most one large portion of any single group
  (`MealPortions.perMealGroupCap`), scaled by `MealShare`. Never sum
  `item.portion.servings` directly into a summary — four fruit rows on one
  platter are one plate of fruit. `MealItem.effectiveServings()` is the one
  place that decides which of `grams`, `servings` and `portion` is authoritative.

- **Two food groups were renamed, and both spellings still resolve.**
  `sofrito` → `cooked_tomato_sauce` and `healthy_fats` → `plant_fats`, because
  both carried a judgement rather than a food description. The raw value moved, so new
  writes use the new spelling; `FoodGroup.init(from:)` and `FoodGroup.value(in:)`
  make the old one keep resolving, for events *and* for the string-keyed tables.
  That second half is the load-bearing one: `shaman-config.json` is fetched from
  one URL by builds of every age, a missed key there is a wrong number with no
  error anywhere, and so the generated table deliberately carries both spellings
  (`LEGACY_GROUP_NAMES` in `build-food-table.py`). `vegetable_oil` is the one
  addition — without it every non-olive oil vanished into nothing, and an
  invisible frying fat was guessed as olive oil.

- **Thresholds and prompts belong in `shaman-config.json`,** not in Swift
  literals, so they can change without a rebuild.
- **Three names per food group, and they are not interchangeable.**
  `displayName` is the formal taxonomy vocabulary and belongs in details or an
  eval; `plainName` is the picker row; `shortName` is a chip and the middle
  of a sentence. Raw values are the on-disk format and move only under the
  both-spellings discipline above — twice ever, and never silently.
- **Sentences, not forms.** The recognised meal is one tappable sentence
  (`FoodSentence`), and at most one ambiguity is ever raised as a question.
  Saving is never blocked on answering it — an ignored question is itself
  recorded, because uncorrected model output is evidence.

- **The identity is Sora, and it ships in the bundle.** One face, 400–800, for
  everything a person reads. It replaced the Space Grotesk / IBM Plex Mono pair
  in August 2026, and with it the rule that mono meant metadata: `WellieMeta`
  survives and still means *this is data about the thing*, but says so with
  uppercasing and tracking rather than with a second typeface.

  What ships is five *static* cuts, not the upstream `Sora[wght].ttf`. iOS
  registers a variable font at its default instance only and offers no way to
  ask `UIFont(name:)` for another, so a bundled variable file renders the whole
  app at 400 while every lookup still succeeds — the silent-and-wrong shape
  again. `scripts/build-fonts.py` cuts them; OFL/SIL, bundled under
  `App/Resources/Fonts` with the licence, declared in `UIAppFonts` in
  `project.yml`, because a font fetched at runtime is a first launch that
  renders in the wrong typeface on a bad connection. `WellieTheme.font` falls
  back to the system face and `EatsomeApp.init` asserts `fontsAreInstalled`.

- **The app is dark, and it is only dark.** Not "has a dark mode": every
  surface, every contrast ratio and the one translucent card on the meal detail
  were drawn against `#0b0d12`, and `EatsomeApp` says so with
  `preferredColorScheme(.dark)`. `WellieTheme`'s colours are single values
  rather than adaptive pairs for the same reason — following the system would
  hand half the users a light app nobody designed.

- **One accent object per screen.** *Ink is reserved for sent text* was the
  previous rule and it went with the thread it governed; on a dark page the
  scarce thing is light, not dark. Periwinkle is spent on the primary button,
  the current selection, and a value that is alive right now. Protein is the
  one nutrient with a colour of its own, because it is the one of the five with
  a *goal* rather than a reference range — a protein bar can honestly be full,
  where an energy bar can only be long or less long.

- **Salt is not on Today.** It is the invariant above ("a floor, and no screen
  may score it against the ceiling") in its load-bearing form: the day card
  draws four meters and salt is deliberately not one of them, because a meter
  implies a ceiling. It appears on the meal detail, printed as `≥`, with
  nothing to compare it to.

- **Carbohydrate and fat show a range, not a target.** `DailyTargets` publishes
  AMDR *ranges* for both and declines to collapse them, because picking a point
  inside 45–65% is a preference the source does not contain. So `NutrientMeter`
  draws a band rather than a denominator. Energy and protein have real numbers
  and get real denominators.

## Screens

The UI implements the approved redesign in the `App redesign with variations`
Claude Design project, turn `4`, option `4a` — *quiet night, olive-free,
days-logged stats on the main screen*. Five screens carry it: `4a·1` Today
(`TodayView`), `4a·2` log a meal (`LogMealSheet`), `4a·3` reading your plate
(`ReadingPlateView`), `4a·4` meal detail (`MealDetailView`, with `MealFixSheet`
behind `Edit ›`), `4a·5` progress (`ProgressScreen`).

Everything else still carries an id from the previous `Eatsome mobile app
redesign` project and has not been redrawn: `2a` onboarding, `2f` history, `2g`
dishes, `2h` add by hand, `2i` settings, plus the tables surfaces. They inherit
the new tokens — the palette and radii are shared — but not the new layouts.
Screen ids appear in the doc comment of each view; if you change a screen, say
which one.

## Model

Two providers behind one `MealRecognizer`, switchable in `WorkshopView` — the
provider switch, the API key and the counters are off the settings screen and
reachable only by tapping the version row five times. Recognition is something
the app does, not something the user configures:

- `gemini-3.6-flash` on the Gemini API's `generateContent`, `responseSchema`,
  `thinkingLevel: low` (`GeminiSession`). **This is production**, on the evals.
- `gpt-5.6-luna` on the OpenAI Responses API, strict JSON Schema,
  `reasoning.effort: low` (`LunaSession`), image detail from
  `OPENAI_IMAGE_DETAIL` (`high`, because `low` bills a flat 85 image tokens and
  cannot read print on packaging).

The app sends its provider on every request, so it overrides the Worker's
`RECOGNITION_PROVIDER`. Production is whichever the *build* names.

Both send the same `MealPrompt.system`. The schemas are separate because the
subsets differ — Gemini rejects `additionalProperties` and spells nullable as a
flag — but both group enums are generated from `FoodGroup.allCases`, so adding a
case propagates to both.

`promptVersion` is `<prompt>/<model>`, and the recognition cache is namespaced by
it: the same photo re-read by the other provider costs a real call, which is the
only way the comparison means anything.

## HealthKit

Date of birth, biological sex, height, weight, body-fat percentage, active and
basal energy, workouts, and sleep are queried from HealthKit and are never
copied into the append-only meal log. Usual activity is inferred only from at
least seven complete active/resting-energy days. Read authorization is
privacy-preserving: denial is indistinguishable from no samples, so the UI must
not claim that access was granted merely because the request completed.
