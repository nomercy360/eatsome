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
- **No calories are ever derived, and none are ever totalled.** A figure
  transcribed off a printed label may be stored, because reading a fact is not
  estimating one, and it stays inert: nothing sums it and no screen shows a
  daily number. Only packaged food carries a label, so a total would be built
  from the packaged fraction of a diet while looking exactly like a total —
  worse than absent. Nothing asks a model for calories from the look of food.
  `ProteinTests` fails on any symbol that aggregates them.
- **No grams or macros in recognition.** The schema and the prompt deal in food
  groups and coarse portions only. Nothing asks a model for a weight.
- **Protein in grams is the single exception**, and it is derived unless a
  label was read — a transcribed panel wins, and is the only protein figure ever
  stored. The derived one is computed on read, never written, so retuning the
  table moves every estimate in the history and no measurement. It is otherwise
  derived, never entered: `Protein.grams(in:)` multiplies group servings by a table in
  `shaman-config.json`. It earns the exception because it is the only macro with
  an absolute daily threshold worth hitting, the only one whose sources are
  discrete enough to estimate from a photograph, and the only one whose target
  computes itself from data already present (body weight, from HealthKit).
  Carbohydrate and fat get no gram targets — that road ends at a calorie
  counter.
- **A meal is dishes; a dish is ingredients.** `count` is how many servings of
  the dish, `size` is how big one is, and an ingredient's `portion` is its share
  of one serving — three independent answers that multiply. `MealEntry` stores
  the dishes and the flat list both, and `MealDish.flattened()` is the only
  thing that writes the flat list; a build from before dishes scores an old meal
  and a new one alike from it.
- **Items are what was seen; `MealEntry.servings(of:)` is what counts.** A meal
  contributes at most one large portion of any single group
  (`MealScoring.perMealGroupCap`), scaled by `MealShare`. Never sum
  `item.portion.servings` directly into a score — four fruit rows on one platter
  are one plate of fruit.
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
