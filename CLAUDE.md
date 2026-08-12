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
  mutations. Nothing rewrites a line of `events.jsonl`. The one exception is
  `Backend/scripts/migrate-v21.mjs`, which rewrote stored payloads once, from a
  backup, and is the reason nothing has to again.

- **Composition is stored, not derived.** A `MealItem` carries `per100g` and the
  app multiplies it by `grams`. That is the whole of the nutrition arithmetic:
  no table, no taxonomy, no config file, no lookup that can miss.

  This replaced a shipped composition table in August 2026, on measurement. The
  table was keyed `kind|label` and matched exactly; recognition writes free text,
  so **78% of logged grams resolved to nothing** and a Subway sandwich showed
  62 kcal because only its cheese matched a row. Asked for the same figures the
  table published, the model reproduced them at **0–3% median error** — 0% when
  the food was named unambiguously (`Backend/eval/composition-recall-poc.ts`).
  The table was not buying accuracy. It was buying auditability, and paying for
  it in silence.

- **Weight is still the only hard number, and still the only one worth
  arguing about.** A photograph shows an amount of food; composition is a food
  database's answer and the model has evidently read the database. Measured
  against Nutrition5k, grams beat the old portion ladder by 11 points of median
  error. That is where the remaining error lives and where measurement should go.

- **Grams are absolute, and nothing multiplies them.** An ingredient's `grams`
  is everything of it present, across every serving. `MealDish.count` is a label
  and a control: changing it rewrites the weights (`scaled(toCount:)`) rather
  than scaling at score time. The old `count × size × portion` product is what
  made one bowl of ramen worth 126 g of protein.

- **One food per `label`, and it is the whole identity.** No kind, no group, no
  code to fall back to. 18% of the distinct labels the table failed to resolve
  named two foods — "ham and bacon", "shredded cabbage and lettuce" — and a row
  that is two foods cannot be priced as either. The prompt forbids "and" as well
  as "or", and `mealRecognitionItemSchema` requires the label.

- **A revision restates the figures it moves.** Stored numbers and editable rows
  can desync: a row renamed from "chicken" to "fried chicken" whose composition
  stayed behind is worse than an uncorrected one, because it looks corrected.
  `per_100g` is required on every `add` and every `revise`, in the Swift type,
  in the Zod contract, and in both provider schemas. A corrected row is stamped
  `user`.

- **A rename that cannot re-price does not happen in the UI.** The food sheet
  (`2d`) offers only the model's own `alternatives`, and each one arrives priced
  — that is why `FoodAlternative` carries a composition block. Anything else is
  a correction in words on the fix screen, where `MealRefiner` re-prices what it
  renames. The v20 picker swapped a food's *name* while a table decided its
  *worth*; with the table gone that is a silent lie.

- **A panel wins figure by figure, not wholesale.** A carton printing protein
  and energy but no sodium contributes two read figures and three from the
  model. `MealDish.nutrients` substitutes; `panelSources` records which.

- **Provenance is per figure: `panel | published | model | user`.** There is no
  `table` case because there is no table — the migration re-priced history
  through the same path a new meal takes, so no stored figure anywhere came from
  a lookup. `published` carries a `SourceRef` with the URL, the market and the
  `scaleBasis`, because a Footlong priced by doubling a Regular is a different
  claim from a printed one.

- **Salt is no longer a floor.** It was one for two years because composition
  tables publish plain preparations — cooked white rice is 1 mg of sodium per
  100 g — and the derived figure ran 82% low on a canteen bibimbap. The prompt
  now says to price food as eaten, seasoning included; asked about guacamole the
  model answers 430 mg where the unsalted avocado row said 8. `saltGrams` is
  shown as a figure, still with no ceiling beside it.

- **The Atwater check replaced unresolved grams as the loud failure.** With a
  table, a bad answer showed up as weight that resolved to nothing. With
  stored composition it would be silent, so `protein × 4 + carbohydrate × 4 +
  fat × 9` against `kcal` is the self-check — stated in the prompt, exported as
  `atwaterDelta` / `ATWATER_TOLERANCE`, tested in `contracts.test.ts`. It read
  2.3% against an official Subway panel.

- **`schemaVersion` is on every meal event, and v21 reads only v21.** No legacy
  decode anywhere in Core. An unversioned event throws rather than decoding to
  something plausible: v20 had no version, guessed, and showed 62 kcal for a
  sandwich instead of an error anyone could see. `ThreadTests` asserts the
  refusal.

- **`dishes` is the only stored form.** `MealEntry.items`, `grams` and
  `nutrients` are computed. v20 stored a flattened list beside the dishes
  because meals predated dishes, and two representations of one thing is how
  they come to disagree.

- **The Gemini response schema is hand-written; everything else is derived.**
  `geminiResponseSchema()` in `Backend/worker/ai/gemini.ts` is the one contract
  not generated from Zod — Gemini rejects `additionalProperties` and spells
  nullable as a flag — and it emits *exactly* the properties it names, dropping
  anything the prompt asks for and it does not declare. That is how v16 shipped
  a weighing prompt that returned no weights. `recognize.test.ts` guards the
  ingredient fields against `mealRecognitionJsonSchema()`, and now guards
  `per_100g` for the same reason: a missing composition block would be a meal
  worth zero calories.

- **Recognition asks for weight and composition, and nothing else numeric.** No
  daily totals, no scores, no confidence. `alternatives` is a shortlist of
  priced rivals, which is what uncertainty looks like when it is useful.

- **Thresholds and prompts belong in `shaman-config.json`,** not in Swift
  literals, so they can change without a rebuild. It no longer carries a food
  table: `nutrientsPerGram` and `proteinPerServing` went with v21.
- **A food has one name, and the model wrote it.** `FoodGroup` had three
  (`displayName`, `plainName`, `shortName`) and `FoodKind` inherited them; both
  are gone. A chip, a sentence and a history row all say `label`, because there
  is no vocabulary left to translate between.
- **Sentences, not forms.** The recognised meal is one tappable sentence
  (`FoodSentence`), and at most one ambiguity is ever raised as a question.
  Saving is never blocked on answering it — an ignored question is itself
  recorded, because uncorrected model output is evidence.

- **The identity is Sora, and it ships in the bundle.** One face, 400–800, for
  everything a person reads. It replaced the Space Grotesk / IBM Plex Mono pair
  in August 2026, and with it the rule that mono meant metadata: `WellieMeta`
  survives and still means *this is data about the thing*, but says so with
  uppercasing and tracking rather than with a second typeface.

  What ships is five *static* cuts, not the upstream `Sora[wght].ttf`. iOS
  registers a variable font at its default instance only and offers no way to
  ask `UIFont(name:)` for another, so a bundled variable file renders the whole
  app at 400 while every lookup still succeeds — the silent-and-wrong shape
  again. `scripts/build-fonts.py` cuts them; OFL/SIL, bundled under
  `App/Resources/Fonts` with the licence, declared in `UIAppFonts` in
  `project.yml`, because a font fetched at runtime is a first launch that
  renders in the wrong typeface on a bad connection. `WellieTheme.font` falls
  back to the system face and `EatsomeApp.init` asserts `fontsAreInstalled`.

- **The app is dark, and it is only dark.** Not "has a dark mode": every
  surface, every contrast ratio and the one translucent card on the meal detail
  were drawn against `#0b0d12`, and `EatsomeApp` says so with
  `preferredColorScheme(.dark)`. `WellieTheme`'s colours are single values
  rather than adaptive pairs for the same reason — following the system would
  hand half the users a light app nobody designed.

- **One accent object per screen.** *Ink is reserved for sent text* was the
  previous rule and it went with the thread it governed; on a dark page the
  scarce thing is light, not dark. Periwinkle is spent on the primary button,
  the current selection, and a value that is alive right now. Protein is the
  one nutrient with a colour of its own, because it is the one of the five with
  a *goal* rather than a reference range — a protein bar can honestly be full,
  where an energy bar can only be long or less long.

- **Salt is not on Today.** The day card draws four meters and salt is
  deliberately not one of them, because a meter implies a ceiling and no
  reference here is one worth scoring against. It appears on the meal detail as
  a plain figure — the `≥` went with the table that made it a floor — still with
  nothing beside it to compare it to.

- **Carbohydrate and fat show a range, not a target.** `DailyTargets` publishes
  AMDR *ranges* for both and declines to collapse them, because picking a point
  inside 45–65% is a preference the source does not contain. So `NutrientMeter`
  draws a band rather than a denominator. Energy and protein have real numbers
  and get real denominators.

## Screens

The UI implements the approved redesign in the `App redesign with variations`
Claude Design project, turn `4`, option `4a` — *quiet night, olive-free,
days-logged stats on the main screen*. Five screens carry it: `4a·1` Today
(`TodayView`), `4a·2` log a meal (`LogMealSheet`), `4a·3` reading your plate
(`ReadingPlateView`), `4a·4` meal detail (`MealDetailView`, with `MealFixSheet`
behind `Edit ›`), `4a·5` progress (`ProgressScreen`).

Everything else still carries an id from the previous `Eatsome mobile app
redesign` project and has not been redrawn: `2a` onboarding, `2f` history, `2g`
dishes, `2h` add by hand, `2i` settings, plus the tables surfaces. They inherit
the new tokens — the palette and radii are shared — but not the new layouts.
Screen ids appear in the doc comment of each view; if you change a screen, say
which one.

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
flag — and both are now hand-listed field by field, so a field added to one must
be added to the other. `recognize.test.ts` and the two session tests are what
catch it when it is not; there is no generated enum left to propagate.

`promptVersion` is `<prompt>/<model>`, and the recognition cache is namespaced by
it: the same photo re-read by the other provider costs a real call, which is the
only way the comparison means anything.

## HealthKit

Date of birth, biological sex, height, weight, body-fat percentage, active and
basal energy, workouts, and sleep are queried from HealthKit and are never
copied into the append-only meal log. Usual activity is inferred only from at
least seven complete active/resting-energy days. Read authorization is
privacy-preserving: denial is indistinguishable from no samples, so the UI must
not claim that access was granted merely because the request completed.
