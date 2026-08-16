# eatsome

Say what you ate; the day keeps the count.

A calorie tracker for iOS. Photograph a plate or type a sentence, and a model
returns the dishes on it, each food's weight in grams and its composition per
100 g. The app stores that, multiplies, and shows the day against a reference.
That is the whole product.

Canonical domain: [eatsome.co](https://eatsome.co); the App Store listing is
named `eatsome.co`. The bundle identifier (`app.shaman.tracker`) and this
repository's name are App Store identity from before the rename and are not
going to change; everything a person sees says eatsome.

## What it deliberately does not do

**Nothing asks the model for a total.** Recognition reports weight and per-100 g
composition, per food. Energy, protein, carbohydrate, fat, sodium and alcohol
are `grams × per100g`, on the phone, from figures that were stored with the meal.
There is no lookup that can miss and no total that can be secretly partial.

**No score, no rating, no streak.** The counter on Today counts days logged. The
app can see what it was told about and nothing else, and a number that dimmed
because of what you ate would turn a record into a report card.

**No social, no movement, no weight tracking.** Each of those shipped once and
was removed in August 2026 when the product was cut back to the one thing.

**No silent cloud dependency.** The phone's append-only log is the record; the
Worker mirrors it. Both directions are a union of immutable events, so a
reinstall recovers history by pulling and nothing ever deletes by comparison.

## Layout

```
Core/            SwiftPM package EatsomeCore — no frameworks, fully tested
  Model/         UUIDv7, epoch time, MealEntry/MealDish/MealItem, the five event kinds
  Nutrition/     Nutrients arithmetic + Atwater check, NutritionProfile, DailyTargets
  AI/            wire types (MealRecognition, MealRevision) and BackendSession
  Storage/       JSONL EventLog, byte-faithful RawJSON, EventCodec, KeychainStore
App/             SwiftUI
  Eatsome/       every screen, plus EatsomeStore (the log) and EatsomeAccount (the Worker)
  Support/       HealthKit (read-only), camera and photo store, Sign in with Apple
  DesignSystem/  WellieTheme tokens (light and dark pairs), FlowLayout
Backend/         Cloudflare Worker — Hono, D1/Drizzle, private R2, Gemini proxy
prompts/         one Markdown file per prompt version; generated into the Worker
scripts/         bootstrap, fonts, TestFlight
```

`Core` has no dependency on UIKit, AVFoundation or HealthKit; the log, the
arithmetic and the wire contracts are testable without an iOS runtime.

## Setup

Requires Xcode and XcodeGen.

```bash
./scripts/bootstrap.sh          # generates eatsome.xcodeproj from project.yml
```

Open the project, select a development team, run it on an iPhone (HealthKit is
unavailable on macOS). Sign in with Apple on first launch; the session it mints
is the only credential. No model-provider key ever ships in the app.

```bash
swift test --package-path Core                          # with Xcode
SHAMAN_TESTING_PACKAGE=1 swift test --package-path Core # bare Command Line Tools
cd Backend && npx vitest run                            # the Worker
./scripts/release-testflight.sh --upload                # tests, archives, uploads
```

## How it works

### The log

`events.jsonl` in Application Support, one JSON value per line, never rewritten.
Five event kinds: `meal_logged`, `meal_revised`, `meal_deleted`, `message_sent`,
`message_deleted`. A correction is a new `meal_revised` beside the original; the
read model (`Projection`) is a fold over the file. Every meal event carries
`schemaVersion: 1` and refuses to decode as anything else. A kind this build does
not know is kept byte for byte and folds into nothing, so a newer phone on the
same account is not a breaking change.

### Recognition

The phone sends the photo (2048 px, re-encoded, SHA-256 as its name) and/or the
words to the Worker; the Worker calls `gemini-3.7-flash` with a response schema,
the current prompt from `prompts/`, Google Search as a tool, and the request's
country. The answer is dishes → ingredients, each with `grams`, `per_100g`
(seven figures), optional priced-and-weighed `alternatives`, optional brand and
published sizes, and a printed nutrition panel when one is legible. The Worker
caches by (photo, words, country, prompt version, model). Weight is the only hard
number; the composition is a food table the model has evidently read, measured
at 0–3% median error against the published rows.

### Correction

"Fried in butter" is sent with the current list and comes back as a delta
(`MealRevision`): rows to add, revise or remove, each restating `per_100g`.
Everything the words did not name survives; corrected rows are stamped `user`.
The pick sheet offers only the model's own alternatives, because a rename that
cannot re-price is a silent lie.

### The reference

`NutritionProfile` (age, reference sex, height, weight, activity, goal) →
`DailyTargets` from the 2023 adult DRI equations. Protein is a goal in g/kg,
fat is 30% of energy, carbohydrate is the remainder — one figure each, one rule
each. HealthKit can fill the blank fields, read-only, and never enters the meal
log.

### Sync

Pull `GET /v1/events?after=<cursor>` until the cursor is nil and append every
line the phone lacks, verbatim; push the whole local log with
`POST /v1/events/batch` (idempotent by id); fetch back any meal photo missing on
disk. Deletion is a `meal_deleted` event like any other write. Runs at launch, on
sign-in and on return to the foreground.

See [`Backend/README.md`](Backend/README.md) for the Worker.

## Status

In TestFlight with test accounts only. Nothing in the log or the Worker's
schema is versioned for compatibility with earlier builds, deliberately: there
are no earlier installs worth carrying.
