# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

People who want to eat better and have bounced off calorie counting — a broad
consumer audience reached through the App Store rather than a niche of
quantified-self users. They are not weighing food, not reading labels, and not
willing to spend a minute per meal on data entry.

The situation is a plate in front of them and about ten seconds of attention: at
a table, in a canteen, on a train. A meal is often logged *after* it was eaten —
written up at bedtime — and the product treats that as normal rather than as a
lapse.

A second, smaller audience exists today and is not the target: the author and a
handful of TestFlight testers, whose real logged meals are the evidence the
recognition work is measured against.

## Product Purpose

Say what you ate — as a photograph, a sentence, or a voice note — and get a
score for the week against a diet you choose.

The app reads the meal into food groups and weights, then scores a rolling
seven-day window. Success is **a week you keep logging**: the score is only
worth anything if the days are actually in it, so every design decision is
weighed against whether somebody will still be logging on day forty. That is why
the window is seven days rather than one (no fish on Tuesday is not a failure),
why the bottom of the olive scale is "a treat — it happens" rather than a
reprimand, and why a wrong reading is corrected in a sentence instead of a form.

## Positioning

**Nothing asks a model for a number except a weight.**

A vision model asked how many calories are on a plate returns a figure with
30–50% error that is indistinguishable from data. Asked what something weighs,
it is reading the photograph. So recognition reports one quantity — grams — and
every other figure (energy, protein, carbohydrate, fat, sodium) is `grams × per
100 g` from a published composition row that the app can name.

Two consequences a neighbouring product could not truthfully copy without doing
the same work:

- **Every figure traces to a source row.** USDA SR Legacy (2018-04, frozen) and
  MEXT 8th revision, pinned and checked into the config. A row that cannot be
  resolved is a build failure, not a default.
- **A total is only allowed when every food group can answer.** Food the app did
  not recognise lands in `unresolvedGrams`, which every screen showing a total
  must surface. A partial total that does not say it is partial is the failure
  the whole design is arranged against.

The diet is data rather than a mode: switching it re-scores the entire history
instantly, because no score was ever stored — only the parse.

## Operating Context

- **Capture is one field.** Camera, photo library, keyboard, microphone — all
  four reach the same composer, and none of them is a separate screen.
- **Logging is retrospective as often as not.** Eaten time and logged time are
  different facts; the day reads in eaten order with a quiet stamp when they
  differ.
- **Correction is conversational.** A wrong weight or a wrong food is fixed by
  saying so in words; the model returns a delta touching only the rows it names,
  so hand edits survive.
- **At most one question per meal.** Which ambiguity is worth a tap is computed
  from the active diet, so the question changes when the diet does. Saving is
  never blocked on answering, and an ignored question is itself recorded as
  evidence.
- **Health data is read, never written.** Workouts, sleep and weight are read
  from HealthKit at launch and never copied into the log.
- **Tables** — small groups of friends, capped at twelve — are where a meal can
  be shared. The score never travels with it.

## Capabilities and Constraints

**Confirmed functionality.** Photo/text/voice recognition; food-group and gram
extraction; five nutrients derived by table lookup; transcription of printed
nutrition panels when one is legible; a diet engine with five shipped presets and
user-forked custom diets; goals scored into olives and constraints reported
kept-or-broken; an optional protein target; a seven-day window; HealthKit import;
tables with posts, replies, reactions and shared photos; Sign in with Apple.

**Technical constraints that are not negotiable without a decision.**

- Storage is an append-only event log. Corrections are new lines; nothing
  rewrites history, and new fields on stored types must be optional.
- `Core/` is framework-free — no UIKit, AVFoundation, MediaPipe or HealthKit —
  which is what makes the scoring testable.
- Time is UTC epoch milliseconds; local time is derived at render. Identifiers
  are UUIDv7.
- Thresholds, prompts and nutrient tables live in `shaman-config.json`, fetched
  at launch, so they change without a rebuild. That file is fetched from one URL
  by builds of every age, which constrains how its keys may change.
- The recognition prompt is one Markdown file generated into both Swift and
  TypeScript; the two must never drift.

**Explicitly undecided.**

- **Distribution.** The intent is a broad consumer App Store app, but the app
  today requires a backend token baked in at build time and has no store
  presence or pricing. Nothing downstream may assume a
  public release date or a business model.
- **Sign-in is required.** Sign in with Apple is the production identity
  boundary, shown before onboarding or an existing local log. The shared build
  token can start the identity exchange but cannot access meals, recognition,
  voice, or tables by itself. A week follows the signed-in account to another
  phone; local history remains on disk after sign-out but stays locked until an
  account is authenticated again.
- **Push notifications** are not built. Table badges are polled on open and every
  response states when the server counted it.
- **Macro targets beyond protein.** Energy, carbohydrate and fat are computed and
  shown, but no target is offered for them, on the argument that a target invites
  eating to a number that is only as good as an estimated weight.

## Brand Commitments

- **The product is called eatsome.** `shaman` — the repository name, the bundle
  identifier `app.shaman.tracker`, and the `Shaman` application-support
  directory — is legacy plumbing retained so existing installs keep their
  history. It must never appear in anything a person reads.
- **Olives are the score.** One to five, and the unit every diet shares, so a
  plant-forward week and a Mediterranean week read the same at a glance.
- **Sentences, not forms.** The recognised meal is one tappable sentence. Numbers
  small enough to speak are spelled as words in prose, because a digit
  mid-sentence reads as data and the point of the sentence is that it is not.
- **The tone is additive.** One olive is a treat, never a failure. There is no
  screen that tells somebody off.
- **A score is private.** Sharing a meal shares a dish, a photograph, and — only
  if switched on — what was in it. There is deliberately no control that would
  make olives travel to somebody else's feed.

## Evidence on Hand

Real, in the repository:

- `Backend/eval/` — a scored evaluation harness with golden sets for photo and
  text input, run through promptfoo against both providers.
- Nutrition5k, whose ingredients were weighed on a scale as they went onto the
  plate: measured 26% median error for absolute grams against 37% for the
  three-step portion ladder it replaced, and the ladder under-read systematically
  (×0.68 on plates over 45 g of protein).
- 220 hand-weighed dishes used to establish that a dish multiplier made the
  estimate worse on every figure that matters.
- A canteen bibimbap printing 4 g of salt against a derived 0.7 g — the
  measurement behind showing salt as a floor (`≥`) and never against a ceiling.
- MEDAS, the Mediterranean Diet Adherence Screener from the PREDIMED trial: the
  one shipped diet that is a published instrument, and the only one allowed to
  say so.
- TestFlight feedback and screenshots from real testers.

Absences that future work must not fabricate: there are no customers, no
testimonials, no usage numbers, no press, no pricing, and no clinical validation
of anything except MEDAS itself — and MEDAS validates the screener, not this
app's implementation of it.

## Product Principles

1. **A plausible number is worse than none.** Anything the app cannot establish
   is absent, marked partial, or shown as a floor — never filled in with
   something that looks like data.
2. **The person is the authority on their own meal.** Their words outrank the
   model's reading of the photograph, and a correction is kept as evidence rather
   than overwriting what the model thought.
3. **Never require perfection to stay useful.** A rolling window, a forgiving
   scale, skippable questions, and a log that works offline — because the failure
   mode that kills this product is somebody quietly stopping in week three.
4. **The diet belongs to the user, the measurement belongs to the app.** What
   counts as a good week is a choice; what is on the plate is a reading. Those
   two are kept apart, which is what lets the diet change without the history
   changing.
5. **Say what it cost.** Estimates state that they are estimates, snapshots state
   when they were taken, and a claim that only one diet earns — "validated" —
   belongs to the one instrument that earned it.

## Accessibility & Inclusion

**VoiceOver and Dynamic Type are committed, and implemented.** The commitment
follows from the audience: a broad consumer app cannot ship a reading size
setting that does nothing.

What that means concretely, and what future work must not regress:

- Every text size scales. Both font functions go through
  `Font.custom(_:size:relativeTo:)` against a matched text style, so the
  hierarchy survives the accessibility sizes instead of a caption overtaking a
  heading.
- Layouts reflow rather than clip at the accessibility sizes. The day timeline
  moves its time above the entry and the day's glance stacks, because scaled
  proportionally both took a third of the screen from the food.
- Every tappable control has a 44 pt hit area, whatever it draws.
- Every icon-only control is labelled, and a reaction announces its count.
- Reduce Motion is honoured in both places the app animates.
- Text meets contrast in both appearances. `faint` is decoration-only, measured
  at 2.5:1; anything with words in it uses `muted` at 4.97:1 or better.

Not yet established: a formal WCAG-equivalent audit, VoiceOver rotor support,
and Switch Control testing. Those are undecided rather than claimed.
