# Working in this repo

eatsome is a calorie tracker and nothing else: say what you ate — a photograph
or a sentence — and the day keeps the count. Everything below exists to keep
that one number honest.

## Build and test

```bash
swift test --package-path Core          # needs Xcode's toolchain
cd Backend && npx vitest run            # the Worker
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

```
Core/Sources/EatsomeCore/   framework-free: model, log, arithmetic, wire types, Worker client
App/Eatsome/                the screens and the two lanes they read from (store, account)
App/Support/                anything that touches a framework: HealthKit, camera, photos, Keychain UI
App/DesignSystem/           WellieTheme tokens, FlowLayout
Backend/                    Cloudflare Worker: recognition proxy, event mirror, media, sign-in
prompts/                    the recognition and correction prompts, one file per version
```

`Core/` must not import UIKit, AVFoundation or HealthKit. That constraint is
what makes the log, the arithmetic and the wire contracts testable on any
machine with a Swift toolchain, and it is worth defending. HealthKit is isolated
in `App/Support/HealthKitBridge.swift` and only ever *reads* a body profile.

The bundle identifier is still `app.shaman.tracker` and the repository is still
`shaman`. Those are App Store identity and are not to be renamed; everything a
person sees says eatsome, the domain is eatsome.co, and the App Store listing
is named `eatsome.co`.

## Invariants

- **Time is `EpochMillis`, UTC.** No `Date` in any stored type; local time is
  derived at render time.
- **IDs are `UUIDv7.generate()`.** Never `UUID()` for anything persisted.
- **Storage is append-only.** `events.jsonl` is one JSON value per line, never
  rewritten. Corrections are `mealRevised` events, deletions are `mealDeleted`
  events. Five kinds exist (`Event.swift`); a kind this build does not know is
  retained byte for byte as `.unrecognized` and folds into nothing.

- **The mirror is a union, and nothing deletes by comparison.** Events are
  immutable and named by id, so a phone and the Worker converge by pulling what
  the phone lacks (`GET /v1/events?after=<cursor>`, verbatim lines) and pushing
  what the Worker lacks (`POST /v1/events/batch`, idempotent). A reinstall or a
  second phone recovers history by pulling. There is no reconcile-by-snapshot
  and there must not be one: the previous design made the phone authoritative
  and deleted server rows absent from it, which meant a fresh install with an
  empty log could erase the account's history.

- **Composition is stored, not derived.** A `MealItem` carries `per100g` and the
  app multiplies it by `grams`. That is the whole of the nutrition arithmetic:
  no table, no taxonomy, no config file, no lookup that can miss.

  This replaced a shipped composition table in August 2026, on measurement. The
  table was keyed `kind|label` and matched exactly; recognition writes free text,
  so **78% of logged grams resolved to nothing** and a Subway sandwich showed
  62 kcal because only its cheese matched a row. Asked for the same figures the
  table published, the model reproduced them at **0–3% median error** — 0% when
  the food was named unambiguously (`Backend/eval/composition-recall-poc.ts`).

- **Weight is the only hard number, and the only one worth arguing about.** A
  photograph shows an amount of food; composition is a food database's answer
  and the model has evidently read the database. Measured against Nutrition5k,
  grams beat the old portion ladder by 11 points of median error. That is where
  the remaining error lives and where measurement should go.

- **Grams are absolute, and nothing multiplies them.** An ingredient's `grams`
  is everything of it present, across every serving. `MealDish.count` is a label
  and a control: changing it rewrites the weights (`scaled(toCount:)`) rather
  than scaling at score time. The old `count × size × portion` product is what
  made one bowl of ramen worth 126 g of protein.

- **One food per `label`, and it is the whole identity.** No kind, no group, no
  code to fall back to. The prompt forbids "and" as well as "or", and the Zod
  contract requires the label.

- **A revision restates the figures it moves.** A row renamed from "chicken" to
  "fried chicken" whose composition stayed behind is worse than an uncorrected
  one, because it looks corrected. `per_100g` is required on every `add` and
  every `revise`, in the Swift type, in the Zod contract and in the Gemini
  schema. A corrected row is stamped `user`.

- **A rival is priced and weighed, everywhere.** `FoodAlternative` carries
  `per100g` and `grams` because a tuna sub priced at whatever the turkey sub
  weighed is a number that looks chosen and is not. Recognition and correction
  use one wire shape for it (`RecognizedAlternative`); the correction contract
  briefly asked for label and composition only, and any correction that added a
  row with rivals failed to decode.

- **A rename that cannot re-price does not happen in the UI.** The pick sheet
  offers only the model's own `alternatives`, and each one arrives priced.
  Anything else is a correction in words, where the Worker re-prices what it
  renames.

- **A panel wins figure by figure, not wholesale.** A carton printing protein
  and energy but no sodium contributes two read figures and the rest from the
  model. `MealDish.nutrients` substitutes; `panelSources` records which.

- **Provenance is per figure: `panel | model | user`.** No `table` case because
  there is no table; no `published` case because nothing can name a source (see
  grounding, below).

- **Recognition has Google Search available, and that is what fixed branded
  food.** `RECOGNITION_SEARCH=on` adds `googleSearch` as a tool on the same
  `generateContent` call, in the same schema — the model reaches for it on a
  chain's product and ignores it on food nobody published. Measured on a Subway
  JP American Clubhouse footlong, published at 698 kcal: ungrounded 845 and 865,
  grounded 699. It buys accuracy and not provenance: `generateContent` returns
  no grounding metadata beside a response schema, so a grounded answer is a
  better estimate and the app says "estimated" about it.

- **The request's country reaches the model.** Asked "subway american clubhouse
  footlong" with no country, grounding returned 1216 kcal — correctly, for the
  American sandwich. Told the phone is in Japan, the same words return 699.
  `CF-IPCountry` is fenced into the turn as the weakest evidence there is, and
  is part of the cache fingerprint.

- **A chain's product is one row, not a recipe.** Without that bullet in the
  prompt, four runs of one sandwich returned 698, **929**, 698, 698 — the
  outlier rebuilt it from seven components and looked exactly as confident. It
  sits before the decomposition rule because it is a counterweight to it.

- **Salt is priced as eaten and shown with nothing beside it.** Composition
  tables publish plain preparations and the derived figure ran 82% low on a
  canteen bibimbap; the prompt says seasoning included. There is no salt
  ceiling in `DailyTargets` and no salt line on Today, because a figure beside
  a reference implies a reference worth scoring against.

- **The Atwater check is the loud failure.** With stored composition a bad
  answer would be silent, so `protein × 4 + carbohydrate × 4 + fat × 9 +
  alcohol × 7` against `kcal` is the self-check — in the prompt, exported from
  `contracts.ts`, on `Nutrients.atwaterDelta`, tested on both sides.

- **`schemaVersion` is on every meal event and it is `1`.** `MealEntry`
  writes it and refuses anything else (`SchemaError.unsupportedVersion`); such
  a line is corrupt, not "from a newer build". There is no older version to
  read — the only installs are test accounts — and there is no legacy decode
  anywhere in Core. Unknown enum values throw rather than rounding to a
  plausible case.

- **`dishes` is the only stored form.** `MealEntry.items`, `grams` and
  `nutrients` are computed. Two representations of one thing is how they come
  to disagree.

- **The Gemini response schema is hand-written; everything else is derived.**
  `geminiResponseSchema()` in `Backend/worker/ai/gemini.ts` is the one contract
  not generated from Zod — Gemini rejects `additionalProperties` and spells
  nullable as a flag — and it emits *exactly* the properties it names, dropping
  anything the prompt asks for and it does not declare. That is how v16 shipped
  a weighing prompt that returned no weights. `recognize.test.ts` guards it
  field by field against `mealRecognitionJsonSchema()`.

- **Recognition asks for weight and composition, and nothing else numeric.** No
  daily totals, no scores, no confidence. `alternatives` is a shortlist of
  priced rivals, which is what uncertainty looks like when it is useful.

- **The prompt has one source and the phone does not hold it.** `prompts/*.md`
  is generated into the Worker by `scripts/sync-prompt.mjs`; versions are
  immutable and `promptVersion` comes back in every envelope and keys the cache.

- **A food has one name, and the model wrote it.** A chip, a sentence and a
  history row all say `label`.

- **The identity is Sora, and it ships in the bundle** as five *static* cuts —
  iOS registers a variable font at its default instance only, so a bundled
  variable file renders the whole app at 400 while every lookup still succeeds.
  `scripts/build-fonts.py` cuts them; `EatsomeApp.init` asserts they are there.

- **The app follows the phone, and every colour is a pair.** Every token in
  `WellieTheme` is an `adaptive(light:dark:)` pair resolved by
  `UIColor(dynamicProvider:)` at draw time; the root sets no scheme. The 4.5:1
  floor holds on both pages. Reading `@Environment(\.colorScheme)` to choose a
  colour is what the pairs exist to prevent; the one legitimate read is the
  Sign in with Apple button, whose style is an enum Apple owns.

- **One accent object per screen.** Periwinkle is the primary button, the
  current selection, or a value that is alive right now. Protein is the one
  nutrient with a colour of its own, because it is the one of the five with a
  *goal* rather than a reference range.

- **Every macro on Today is one figure, by a stated rule.** Protein is a
  goal in g/kg. Fat is 30% of planned energy (`DailyTargets.fatShare`, the
  middle of the adult AMDR). Carbohydrate is the energy left after protein and
  fat. The AMDR *ranges* stay on `DailyTargets` for anyone who asks, but the
  card compares a number to a number — a range in that slot read as a target
  nobody had set. The rule is the honesty: the figure is derived, and the
  derivation is one sentence.

- **Today is the day, not a report on it.** A date, one card, a timeline. The
  counter counts **days logged**, not a score, because the app can see what it
  was told about and nothing else.

## Screens

Today is drawn from the `App Redesign Final` Claude Design project, turn `13`,
option `13b`, frame `13b·1` (`TodayScreen`). The rest inherits the tokens but
not turn 13's layouts: `LogComposer` (the `+` lane: camera / recent photos /
words, reading, confirm), `MealDetailScreen` with `MealDetailPick`, `MealDetailNote`
and `EatsomeFix` behind Edit, `ProgressScreen` with `ProgressEarlierDays`,
`YouScreen` with `YouNumbersSheet` (the profile and targets), `EatsomeSignIn`,
`EatsomeConsent`. Screen ids appear in the doc comment of each view; if you
change a screen, say which one.

Two lanes feed them: `EatsomeStore` (the log, the projection, the profile) and
`EatsomeAccount` (Keychain, session, the Worker, sync). A screen asks a lane; a
lane folds the log. Nothing else holds state.

## Model

One provider: `gemini-3.7-flash` on `generateContent` with `responseSchema`
and `thinkingLevel: low`, called by the Worker with the Worker's key. The phone
never holds a provider credential and never sends the prompt. The choice was
taken on price, deliberately and with the measurement pointing the other way
(`Backend/eval/models.json`); the discount ends 2026-12-31 and the argument is
due to be re-made before January.

## HealthKit

Date of birth, biological sex, height, weight, body fat and active/basal energy
are read from HealthKit to prefill the profile that `DailyTargets` is computed
from, and are never copied into the meal log. Usual activity is inferred only
from at least seven complete energy days. Read authorization is
privacy-preserving: denial is indistinguishable from no samples, so the UI must
not claim that access was granted merely because the request completed.
