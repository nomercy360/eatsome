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
    Nutrition/   MEDAS criteria and the rolling-window scorer
    Movement/    Experimental pose geometry and rep counter (not shipped in app)
    AI/          Luna client, strict JSON schema, SHA-256 recognition cache
    Storage/     JSONL event log, Keychain
    Config/      Remote-or-bundled tunables
App/             iOS app — SwiftUI, 1024px meal camera input, HealthKit
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

Then add an OpenAI or Gemini API key in Settings. It goes to the Keychain.

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
- A confirmation is required only when a rival would move the MEDAS score in a
  different direction — chicken read as pork does, brown rice read as white does
  not, because no MEDAS item scores grains. A warning on every row is wallpaper.
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

### Protein is the one number in grams

Everything else here is food groups and coarse portions, on purpose. Protein is
the exception, for three reasons that do not apply to the other macronutrients:

- it has an absolute daily threshold with evidence behind it — roughly 1.6–2.2 g
  per kilogram of body weight when building muscle — so it has to be summed in
  grams rather than watched as a ratio;
- its sources are discrete and countable, which is the only reason a photograph
  can estimate it at all. Fat is smeared through the dish and invisible in the
  cooking, and its grams would be fiction;
- its target computes itself from data already here: body weight arrives from
  HealthKit, so the number moves when you do.

It is derived, never entered — group servings times a table in
`shaman-config.json`, which is where you tune it against real meals. Carbohydrate
and fat get no daily gram targets, and nothing anywhere converts any of it to
calories, though it would be easy from the same data. That is the road that ends
at a calorie counter.

Per meal the estimate is loose, and large portions are read low by every model
measured, so the sum leans conservative. Read the trend. If a month of days
lands 15–20 g short, suspect the estimate before the diet.

### A plate is not a serving count

Recognition splits a dish into as many rows as it sees, and that is right for the
correction sheet — you can check what was actually recognized. It is wrong for
the score: a fruit platter read as four rows would clear a daily target from one
photograph. So scoring aggregates per meal, per group, with two rules:

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
The reference screens include calorie and macro concepts that eatsome explicitly
does not adopt; only their visual system and interaction hierarchy are reused.

### HealthKit is the health-data source of truth

eatsome requests read-only access to workouts, sleep analysis, and body mass.
It refreshes a recent snapshot when the app becomes active and does not copy or
modify those samples in its event log. Sleep intervals are merged before totals
are calculated so overlapping sources are not double-counted.

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

`Core` is complete and tested (52 tests). The app supports meal recognition,
rolling MEDAS adherence, and read-only HealthKit imports for workouts, sleep,
and weight. The signed app has been built, installed, and launched on a physical
iPhone with its HealthKit entitlement.
