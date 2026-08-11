# eatsome

A conversational meal log and health overview for iOS.

Canonical domain: [eatso.me](https://eatso.me)

The original bundle, storage-directory, and Keychain service identifiers remain
unchanged internally so the rename installs as an update without losing data.

Two connected loops:

1. **Describe or photograph a meal** → the recognition model classifies dishes,
   food groups, and weights → sourced nutrition figures and a one-to-five olive
   rating for the plate.
2. **Connect Apple Health** → age, sex reference, height, weight, body fat, and
   recent energy data fill a personal daily energy and macro reference when
   available; workouts and sleep still appear in the daily overview.

## What this deliberately does not do

**No model-invented nutrition.** Recognition estimates only the food and its
weight. Energy, protein, carbohydrate, fat, and sodium come from published food
tables or a nutrition panel the model can actually read.

**Meal history, not weekly verdicts.** The app keeps meal-level olive ratings
and daily history without grading the week.

**No silent cloud dependency.** The app still works from its local append-only
log. The new backend is an explicit sync and recognition boundary; it does not
become the only copy of meal history.

**No custom health score.** Workouts, sleep, and weight are shown as recorded by
HealthKit. eatsome does not turn them into a proprietary readiness number.

## Layout

```
Core/            SwiftPM package — all logic, no frameworks, fully tested
  Sources/ShamanCore/
    Model/       UUIDv7, epoch time, food groups, append-only events
    Nutrition/   sourced nutrient totals, serving weights, olive ratings
    Movement/    Experimental pose geometry and rep counter (not shipped in app)
    AI/          Luna client, strict JSON schema, SHA-256 recognition cache
    Storage/     JSONL event log, Keychain
    Config/      Remote-or-bundled tunables
App/             iOS app — SwiftUI, 2048px meal camera input, HealthKit
  DesignSystem/  Wellie-derived color, type, card, chip, and button tokens
  Support/       Read-only HealthKit import and app configuration
Backend/         Cloudflare Worker — Hono, D1/Drizzle, private R2, model proxy
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

Recognition goes through the app-owned Worker, so no model-provider key ever
ships in the app. The build carries one shared Worker token and there is
nothing to enter: every install generates its own id on first launch, and that
id is what keeps one tester's photos, meals and daily quota apart from
another's.

### Installing on a phone that is not here

A cable or the same Wi-Fi covers `devicectl`; anything further away means
TestFlight:

```bash
./scripts/release-testflight.sh --upload
```

Tests, archives Release, exports a signed `.ipa`, uploads it. The build number is
the commit count, so a build in TestFlight maps back to a commit. Internal
testers get it without review, minutes after processing. Without an App Store
Connect API key, drop `--upload` and send `build/eatsome.ipa` with Transporter.

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
- Two providers — `gpt-5.6-luna` and `gemini-3.6-flash` — behind one
  `MealRecognizer`, switched in Settings, each with its own Keychain key. The
  published food-photo benchmarks contradict each other about which tier wins,
  so the app is built to answer that from your own plates instead: every eval row
  is stamped `<prompt>/<model>`, and the cache is namespaced the same way so
  re-reading a plate with the other provider is a real call, not a replay.
- The photo's SHA-256 is the cache key, so the same plate is never billed twice.
- Every item is one tap from a fix, with the model's likely confusions listed
  first — fish/white meat, and missing olive oil.
- Uncertainty is reported as a per-item shortlist of rival groups, never as a
  confidence number: self-scored certainty comes back round and uncalibrated
  (the same 0.56 on the rice and on the unidentifiable meat), while "what else
  could this be" is a question about the food and becomes the correction button.
- At most one uncertainty is raised on a meal card. The model's best guess and
  its shortlist are direct correction buttons; saving never waits for an answer.
- Cost at `detail: low` is roughly $0.20/$1.20 per million tokens. Personal use
  is cents per month.

### The photograph has a ceiling, so there are two ways past it

Home cooking hides its ingredients. French toast is two eggs, milk, sugar, and
the butter it was fried in; the camera sees crust, banana, and shine. No vision
model recovers what is not in the frame, so the app asks you instead — one free
text field, no categories, with the example in the placeholder:

- **before** — "anything the photo won't show?" — because a missing ingredient is
  invisible by definition. You cannot notice the absent eggs in a list that never
  had them, so a repair-after-the-fact flow alone would never catch them;
- **after** — "missing or wrong?" — for when the model misread something you can
  see.

Same mechanism, same slot in the prompt, different moment. The correction asks
the model for a **delta** (`MealRevision`), never a re-run: by the time you type
"fried in butter" you may have fixed groups and portions by hand, and
regenerating the list would throw that work away. Indices are bounds-checked, so
a model that miscounts costs you a change that did not happen rather than a row
edited by accident.

The note is kept with the meal and carried into a **recipe**, which is the real
payoff: home dishes repeat, so describing one once makes every later log of it
start complete. It is also the best possible eval input — plain language saying
exactly what recognition missed, which no JSON diff gives you.

A thumbs up/down sits apart from all of this. Correcting takes attention; a thumb
takes none, and most bad readings are never worth typing about.

### A daily reference begins with the person, not the meal

Onboarding offers Apple Health first. It fills age, the applicable published
sex-reference equation, height, weight, body fat, and usual activity when those
values are available; the next screens ask only for what is missing. Age,
reference equation, height, weight, activity, and a maintain/lose/gain-muscle
goal are required. Body fat is optional and supplies approximate lean mass only.

`NutritionProfile` and `DailyTargets` live in framework-free Core. Maintenance
energy uses the 2023 adult Dietary Reference Intake equations. Carbohydrate and
fat are shown as the published acceptable ranges, not an invented single macro
split. Protein is 0.8 g/kg for maintenance and a 1.6 g/kg planning reference for
weight loss or muscle gain. The selected goal is shown as a separate adjustment
from maintenance: a moderate deficit for loss or a small surplus for muscle
gain. Every calorie figure stays visibly approximate, because a population
equation is a starting point and body-weight trend is the calibration.

This personal reference is different from the day's meal total. Meal energy and
macros are still derived from recognised food weights and published composition
rows; unresolved food makes the total explicitly incomplete. The profile and
manual fallback stay on the device rather than entering the meal event API.

### A plate is not a serving count

Recognition splits a dish into as many rows as it sees, and that is right for the
correction sheet — you can check what was actually recognized. It is wrong for
the summary: a fruit platter read as four rows should still be one eating
occasion. So serving summaries aggregate per meal, per group, with two rules:

- a meal contributes at most one large portion of any single group, because one
  meal is one eating occasion;
- the whole meal is scaled by how much of it you ate (`Ate it all` / `Ate part
  of it`), because the camera sees the dish and not your share of it. Shared
  mezze and batch cooking are otherwise the largest source of overstatement, and
  they land exactly where portion estimates are already biased high.

Both live in `MealEntry.servings(of:)`; `rawServings(of:)` is what is on the
plate, for display.

### The UI has one visual language

The supplied Wellie Figma exports are translated into named SwiftUI tokens in
`App/DesignSystem/WellieTheme.swift`: SF Rounded typography, deep navy text,
blue actions, ice-blue health surfaces, neutral cards, and consistent radii.
The reference screens reuse the visual system and interaction hierarchy while
keeping the energy estimate and macro ranges plainly approximate.

### HealthKit is the health-data source of truth

eatsome requests read-only access to date of birth, biological sex, height, body
mass, body-fat percentage, active and basal energy, workouts, and sleep analysis.
It refreshes a recent snapshot when the app becomes active and does not copy or
modify those samples in its event log. Activity is inferred only when at least
seven complete energy days are available; otherwise it is asked directly. Sleep
intervals are merged before totals are calculated so overlapping sources are not
double-counted.

### The backend preserves the append-only model

The Cloudflare backend uses the same invariants as the device:

- event IDs are idempotency keys, and uploads never mutate prior events;
- cursor sync orders by recorded time and UUID;
- recognition is cached by image + note, prompt version, and model;
- model output and the final human correction are retained as an eval pair;
- exact model-input bytes live privately in R2, never in D1;
- consented corpus crops have separate keys, hashes, provenance, and deletion rules.

See [`Backend/README.md`](Backend/README.md) for local setup and deployment.

## Status

The app supports meal recognition, sourced nutrition figures, meal and day olive
ratings, a personal daily energy and macro reference, history, tables, account
sync, and read-only HealthKit imports for body profile, energy, workouts, and
sleep. The signed app has been built, installed, and
launched on a physical iPhone with its HealthKit entitlement.
