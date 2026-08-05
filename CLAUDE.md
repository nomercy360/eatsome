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
- **No calories, grams, or macros.** Anywhere — not in the schema, not in the
  prompt, not in the UI. This is the core product decision; see README.
- **Items are what was seen; `MealEntry.servings(of:)` is what counts.** A meal
  contributes at most one large portion of any single group
  (`MealScoring.perMealGroupCap`), scaled by `MealShare`. Never sum
  `item.portion.servings` directly into a score — four fruit rows on one platter
  are one plate of fruit.
- **Thresholds and prompts belong in `shaman-config.json`,** not in Swift
  literals, so they can change without a rebuild.

## Model

Two providers behind one `MealRecognizer`, switchable in Settings:

- `gpt-5.6-luna` on the OpenAI Responses API, strict JSON Schema, `detail: low`
  images, `reasoning.effort: low` (`LunaSession`).
- `gemini-3.6-flash` on the Gemini API's `generateContent`, `responseSchema`,
  `thinkingLevel: low` (`GeminiSession`).

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
