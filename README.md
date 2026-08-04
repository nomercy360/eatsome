# Shaman

A personal Mediterranean-diet and daily-movement tracker for iOS.

Two things, and only two:

1. **Photograph a meal** → `gpt-5.6-luna` classifies it into food groups and
   coarse portions → a rolling weekly **MEDAS** adherence score.
2. **Point the phone at yourself** → MediaPipe Pose Landmarker counts reps
   on-device → the set is logged and mirrored into HealthKit.

## What this deliberately does not do

**No calorie counting.** A vision model asked for grams returns a number with
30–50% error that still looks like data — you cannot tell a bad week from a bad
estimate. The Mediterranean diet is defined by food-group frequency anyway, and
that is what a photo can actually establish. The app scores the 14-item
[MEDAS](https://pubmed.ncbi.nlm.nih.gov/22330017/) screener from the PREDIMED
trial.

**No daily perfection.** Scoring is a rolling 7-day window. No fish on Tuesday is
not a failure, and false failures are how habit apps get deleted in week three.

**No backend.** One user, one device: the API key lives in the Keychain and
there is nothing to authenticate against. See *Adding a backend later* below.

**No movement classifier.** You pick the movement from a list. Classification is
the unreliable part of camera-based fitness and it buys nothing here.

## Layout

```
Core/            SwiftPM package — all logic, no frameworks, fully tested
  Sources/ShamanCore/
    Model/       UUIDv7, epoch time, food groups, append-only events
    Nutrition/   MEDAS criteria and the rolling-window scorer
    Movement/    BlazePose topology, geometry, 1€ filter, Schmitt rep counter
    AI/          Luna client, strict JSON schema, SHA-256 recognition cache
    Storage/     JSONL event log, Keychain
    Config/      Remote-or-bundled tunables
App/             iOS app — SwiftUI, camera, MediaPipe, HealthKit
  Pose/          The only files that import MediaPipeTasksVision
scripts/         bootstrap.sh, fetch_model.sh
```

`Core` has no dependency on UIKit, AVFoundation, or MediaPipe. That is what lets
the rep counter be tested against synthetic skeletons in microseconds instead of
against a camera.

## Setup

Requires Xcode (the bare Command Line Tools are not enough — MediaPipe needs an
iOS SDK, and both test frameworks ship inside Xcode).

```bash
./scripts/bootstrap.sh
```

That fetches the pose model, generates `Shaman.xcodeproj` from `project.yml`,
runs `pod install`, and leaves you with `Shaman.xcworkspace`. **Open the
workspace, not the project.**

Then add an OpenAI API key in Settings. It goes to the Keychain.

### Core tests

```bash
swift test --package-path Core
```

Without Xcode installed, pull swift-testing in as a package instead:

```bash
SHAMAN_TESTING_PACKAGE=1 swift test --package-path Core
```

## Design notes

### Everything is an append-only event

`events.jsonl` in Application Support, one JSON object per line, never rewritten.
A correction is stored as a new `meal_revised` event beside the original — "the
model said white meat, I said fish" is the data that tells you whether the prompt
needs work, and an in-place update destroys it. The read model (`Projection`) is
a fold over the file; at personal-tracker volumes that costs milliseconds.

### Recognition is constrained, cached, and correctable

- Strict JSON Schema on the Responses API, with the enum generated from
  `FoodGroup` so the model cannot invent a group.
- The photo's SHA-256 is the cache key, so the same plate is never billed twice.
- Every item is one tap from a fix, with the model's likely confusions listed
  first — fish/white meat, and missing olive oil.
- Cost at `detail: low` is roughly $0.20/$1.20 per million tokens. Personal use
  is cents per month.

### Rep counting is a Schmitt trigger, not a threshold

Joint angles come from MediaPipe's **world** landmarks, in metres, so a knee
angle does not change when you move the phone. A 1€ filter removes residual
jitter without lagging a fast descent. Two thresholds with a dead band between
them mean wobbling at the bottom of a squat cannot produce phantom reps, and a
debounce rejects anything faster than a human.

Thresholds live in `Core/Sources/ShamanCore/Resources/shaman-config.json` with
joints written as names, because you will retune them a dozen times in the first
week of camera testing.

### Adding a backend later costs a day, not a week

The groundwork is already there, and none of it was expensive:

- IDs are UUIDv7 — time-ordered, so merging logs is a sort.
- Time is UTC epoch millis everywhere; local time is a render-time concern.
- Storage is an append-only log, so sync is concatenate-and-dedupe.
- Model calls sit behind `MealRecognizer`, so a proxy is a new conformance.

The moment it becomes necessary is specific and recognisable: when a build goes
to a second person.

## Status

`Core` is complete and tested (50 tests). The app layer is scaffolding — it
compiles against the APIs described above but has not been run on a device yet,
because the thresholds are guesses until a real camera disagrees with them.
