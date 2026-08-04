# eatsome

A personal Mediterranean-diet and health overview for iOS.

Canonical domain: [eatso.me](https://eatso.me)

The original bundle, storage-directory, and Keychain service identifiers remain
unchanged internally so the rename installs as an update without losing data.

Two connected loops:

1. **Photograph a meal** → `gpt-5.6-luna` classifies it into food groups and
   coarse portions → a rolling weekly **MEDAS** adherence score.
2. **Connect Apple Health** → workouts, sleep stages, and weight recorded by
   Apple Watch, smart scales, and the Health app appear in one daily overview.

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

**No custom health score.** Workouts, sleep, and weight are shown as recorded by
HealthKit. eatsome does not turn them into a proprietary readiness number.

## Layout

```
Core/            SwiftPM package — all logic, no frameworks, fully tested
  Sources/ShamanCore/
    Model/       UUIDv7, epoch time, food groups, append-only events
    Nutrition/   MEDAS criteria and the rolling-window scorer
    Movement/    Experimental pose geometry and rep counter (not shipped in app)
    AI/          Luna client, strict JSON schema, SHA-256 recognition cache
    Storage/     JSONL event log, Keychain
    Config/      Remote-or-bundled tunables
App/             iOS app — SwiftUI, meal camera, OpenAI, HealthKit
  DesignSystem/  Wellie-derived color, type, card, chip, and button tokens
  Support/       Read-only HealthKit import and app configuration
scripts/         bootstrap.sh
```

`Core` has no dependency on UIKit, AVFoundation, HealthKit, or other app
frameworks. Logic remains testable without an iOS runtime.

## Setup

Requires Xcode and XcodeGen.

```bash
./scripts/bootstrap.sh
```

That generates `eatsome.xcodeproj` from `project.yml`. Open the project, select a
development team, and run it on an iPhone; HealthKit is unavailable on macOS.

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

### The UI has one visual language

The supplied Wellie Figma exports are translated into named SwiftUI tokens in
`App/DesignSystem/WellieTheme.swift`: SF Rounded typography, deep navy text,
blue actions, ice-blue health surfaces, neutral cards, and consistent radii.
The reference screens include calorie and macro concepts that eatsome explicitly
does not adopt; only their visual system and interaction hierarchy are reused.

### HealthKit is the health-data source of truth

eatsome requests read-only access to workouts, sleep analysis, and body mass.
It refreshes a recent snapshot when the app becomes active and does not copy or
modify those samples in its event log. Sleep intervals are merged before totals
are calculated so overlapping sources are not double-counted.

### Adding a backend later costs a day, not a week

The groundwork is already there, and none of it was expensive:

- IDs are UUIDv7 — time-ordered, so merging logs is a sort.
- Time is UTC epoch millis everywhere; local time is a render-time concern.
- Storage is an append-only log, so sync is concatenate-and-dedupe.
- Model calls sit behind `MealRecognizer`, so a proxy is a new conformance.

The moment it becomes necessary is specific and recognisable: when a build goes
to a second person.

## Status

`Core` is complete and tested (50 tests). The app supports meal recognition,
rolling MEDAS adherence, and read-only HealthKit imports for workouts, sleep,
and weight. The signed app has been built, installed, and launched on a physical
iPhone with its HealthKit entitlement.
