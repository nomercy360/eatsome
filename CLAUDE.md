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
  packaged fraction of a diet while looking exactly like a total.

- **A total is only allowed when every food group can answer.** That is the
  condition the paragraph above turns on, so it is a test rather than a
  convention: `FoodNutrientTableTests.everyGroupHasARepresentative` requires a
  sourced `GROUP_REPRESENTATIVE` row for all 26 groups but `other`. `other` has
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
- **`ServingWeight` converts weight to servings, and is not a nutrition table.**
  It says what one MEDAS serving of a group weighs, nothing about what is in it.
  Its alcohol row is wrong by construction and says so: MEDAS counts drinks, and
  a drink is defined by ethanol rather than volume.
- **A transcribed panel wins figure by figure, not wholesale.** A printed
  number is a fact and beats the table for that nutrient only; a carton printing
  protein and energy but no sodium contributes two read figures and three
  derived ones. Discarding the ingredients over a partial panel, or the panel
  over a missing field, both throw away something true. Everything derived is
  computed on read and never written, so retuning `shaman-config.json` moves
  every estimate in the history and no measurement.

- **Targets are floors, ranges, and one ceiling, and the type says which.**
  `DailyTargets` derives all of them from body weight (HealthKit) and
  `Protein.Intent`. Protein is a floor to reach; energy, carbohydrate and fat
  are ranges to sit inside; salt is a ceiling. A screen that draws them all as
  identical meters says they are the same kind of thing and invites eating to
  each — which is why only protein gets a meter on Today. Nothing here uses
  Mifflin-St Jeor: it needs height, age and sex, and asking for a birth date to
  sharpen a number nobody should hit exactly is a bad trade.
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
  (`MealScoring.perMealGroupCap`), scaled by `MealShare`. Never sum
  `item.portion.servings` directly into a score — four fruit rows on one platter
  are one plate of fruit. `MealItem.effectiveServings()` is the one place that
  decides which of `grams`, `servings` and `portion` is authoritative.
- **Thresholds and prompts belong in `shaman-config.json`,** not in Swift
  literals, so they can change without a rebuild.
- **Three names per food group, and they are not interchangeable.**
  `displayName` is the screener's vocabulary and belongs next to a score or in
  an eval; `plainName` is the picker row; `shortName` is a chip and the middle
  of a sentence. Raw values are the on-disk format and never move. The same
  split applies to the fourteen items: `MedasItem.title` states the rule,
  `MedasCopy.plainTitle` says it out loud.
- **Sentences, not forms.** The recognised meal is one tappable sentence
  (`FoodSentence`), and at most one ambiguity is ever raised as a question.
  Saving is never blocked on answering it — an ignored question is itself
  recorded, because uncorrected model output is evidence.

## Screens

The UI implements the approved redesign in the `Eatsome mobile app redesign`
Claude Design project, screen for screen: `2a` onboarding, `1b`/`2b` Today,
`2c` My week, `3a`/`3c` the camera chooser, `2d` reading and failure, `1b Add
meal` the result, `2e` meal detail, `2f` history, `2g` dishes, `2h` add by
hand, `2i` settings. Screen ids appear in the doc comment of each view; if you
change a screen, say which one.

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

Workouts, sleep, and weight are queried from HealthKit and are never copied into
the append-only event log. Read authorization is privacy-preserving: denial is
indistinguishable from no samples, so the UI must not claim that access was
granted merely because the authorization request completed.
