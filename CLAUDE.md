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
  mutations. Nothing rewrites a line of `events.jsonl`.
- **No calories, grams, or macros.** Anywhere — not in the schema, not in the
  prompt, not in the UI. This is the core product decision; see README.
- **Thresholds and prompts belong in `shaman-config.json`,** not in Swift
  literals, so they can change without a rebuild.

## Model

`gpt-5.6-luna` on the OpenAI Responses API, strict JSON Schema, `detail: low`
images, `reasoning.effort: low`. The schema's group enum is generated from
`FoodGroup.allCases` — add a case there and it propagates.

## HealthKit

Workouts, sleep, and weight are queried from HealthKit and are never copied into
the append-only event log. Read authorization is privacy-preserving: denial is
indistinguishable from no samples, so the UI must not claim that access was
granted merely because the authorization request completed.
