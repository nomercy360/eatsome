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
./scripts/bootstrap.sh                  # xcodegen + pod install + model download
```

Never hand-edit `Shaman.xcodeproj` — edit `project.yml` and regenerate.

## Where things go

`Core/` is framework-free. It must not import UIKit, AVFoundation, MediaPipe, or
HealthKit. That constraint is what makes the rep counter testable against
synthetic skeletons, and it is worth defending.

Anything that touches a framework goes in `App/`. `MediaPipeTasksVision` is
imported by exactly one file, `App/Pose/MediaPipePoseProvider.swift`, behind the
`PoseProvider` protocol.

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

## Pose

BlazePose 33-landmark topology. Angles are computed from **world** landmarks
(metres, hip-centred), never from normalized image coordinates — that is the
whole reason for choosing MediaPipe over Vision's 19-point 2D output, and it is
what makes thresholds independent of camera placement.

The same topology backs ML Kit on Android, so thresholds calibrated here port.

## Provenance

`MediaPipePoseProvider` was written against Google's published Pose Landmarker
iOS API. Do not copy or adapt pose-tracking, rep-counting, or verifier code from
any other project into this repo — the counting logic here is derived from the
geometry and belongs to this codebase.
