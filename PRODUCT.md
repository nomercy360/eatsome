# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

People who want to know what they ate and have bounced off calorie counting — a
broad consumer audience reached through the App Store rather than a niche of
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

Say what you ate — a photograph or a sentence — and the day keeps the count.

That is the whole product: a meal becomes dishes, foods and weights, each food
priced per 100 g, and the day shows energy, protein, carbohydrate and fat
against a personal reference. Success is **a log you keep using**: every design
decision is weighed against whether somebody will still be logging on day forty.
That is why a wrong reading is corrected in a sentence instead of a form, and
why nothing on the screen grades the day.

## Positioning

**Nothing asks the model for a total.**

A vision model asked how many calories are on a plate returns a figure with
30–50% error that is indistinguishable from data. Asked what something weighs,
it is reading the photograph; asked what a named food is made of per 100 g, it
is reciting a food table it has evidently read, at 0–3% median error. So
recognition reports two things per food — grams and composition — and every
total is `grams × per 100 g`, on the phone, from figures stored with the meal.

Two consequences a neighbouring product could not truthfully copy without doing
the same work:

- **A total is never secretly partial.** Every food carries its own figures, so
  there is no lookup that can miss and no "unresolved" residue hidden in a sum.
- **A correction re-prices what it renames.** Renaming "chicken" to "fried
  chicken" restates the composition, in the contract, or it does not happen.

## Operating Context

- **Capture is one field.** Camera, photo library and keyboard all reach the
  same composer, and none of them is a separate screen.
- **Logging is retrospective as often as not.** Eaten time and logged time are
  different facts; the day reads in eaten order with a quiet stamp when they
  differ, and the composer has a date.
- **Correction is conversational.** A wrong weight or a wrong food is fixed by
  saying so in words; the model returns a delta touching only the rows it names,
  so hand edits survive. The pick sheet offers only the model's own priced
  alternatives.
- **Health data is read, never written.** A body profile is read from HealthKit
  to fill the reference and never copied into the meal log.
- **The log is the record; the cloud is a mirror.** Append-only on the phone,
  mirrored to the Worker as a union of immutable events in both directions, so
  a reinstall or a second phone recovers history and nothing deletes by
  comparison.

## Capabilities and Constraints

**Confirmed functionality.** Photo and text recognition into dishes, foods,
grams and per-100 g composition, with Google Search grounding for branded food;
transcription of printed nutrition panels when one is legible; correction in
words; an adult daily energy and macro reference from body profile, activity and
goal; Today, earlier days, and a trend; HealthKit prefill of the profile; Sign in
with Apple; two-way sync of the log and private meal photos.

**Technical constraints that are not negotiable without a decision.**

- Storage is an append-only event log. Corrections and deletions are new lines;
  nothing rewrites history.
- `Core/` is framework-free — no UIKit, AVFoundation or HealthKit — which is
  what makes the domain logic testable.
- Time is UTC epoch milliseconds; local time is derived at render. Identifiers
  are UUIDv7. Every meal event carries `schemaVersion: 1`.
- The recognition prompt is one Markdown file per version, generated into the
  Worker; the phone never holds it. Versions are immutable.
- One model provider, Gemini, called by the Worker with the Worker's key.

**Explicitly undecided.**

- **Distribution.** The intent is a broad consumer App Store app, but the app
  has no store presence or pricing. Nothing downstream may assume a public
  release date or a business model.
- **Push notifications** are not built.
- **Voice input.** Dictation shipped once through a third-party transcription
  service and was removed with the cut to one thing; on-device speech is the
  obvious way back if it returns.
- **Profile sync.** The body profile stays on the device; only meal events and
  photos are mirrored.

## Brand Commitments

- **The product is called eatsome.** `shaman` — the repository name and the
  bundle identifier `app.shaman.tracker` — is App Store identity from before
  the rename. It must never appear in anything a person reads.
- **The tone is additive.** There is no score, no rating, no streak, and no
  screen that tells somebody off. The one counter counts days logged.
- **A food has one name, and the model wrote it.** A chip, a sentence and a
  history row all say the same label.
- **Every figure says what it is.** A model's estimate says "estimated"; a
  figure read from a printed panel says so; a corrected row is marked as the
  person's.

## Evidence on Hand

Real, in the repository (`Backend/eval/`):

- Nutrition5k, whose ingredients were weighed on a scale as they went onto the
  plate: 26% median error for absolute grams against 37% for the three-step
  portion ladder it replaced, and the ladder under-read systematically.
- 220 hand-weighed dishes used to establish that a dish multiplier made the
  estimate worse on every figure that matters.
- The composition-recall measurement (0–3% median error against published rows)
  that retired the food table, and the branded-food runs (Subway JP, 698 kcal
  published: 845/865 ungrounded, 699 grounded) that put search on the call.
- A canteen bibimbap printing 4 g of salt against a derived 0.7 g — the
  measurement behind pricing food as eaten, seasoning included.
- TestFlight feedback and screenshots from real testers.

Absences that future work must not fabricate: there are no customers, no
testimonials, no usage numbers, no press, no pricing, and no clinical validation
of the app's nutrition estimates.

## Product Principles

1. **A plausible number is worse than none.** Anything the app cannot establish
   is absent or says it is estimated — never filled in with something that looks
   like data.
2. **The person is the authority on their own meal.** Their words outrank the
   model's reading of the photograph, and a correction is kept as evidence rather
   than overwriting what the model thought.
3. **Never require perfection to stay useful.** A log that works offline and
   never blocks a save — because the failure mode that kills this product is
   somebody quietly stopping in week three.
4. **Say what it cost.** Estimates state that they are estimates, and every
   derived reference states its rule.

## Accessibility & Inclusion

**VoiceOver and Dynamic Type are committed, and implemented.** The commitment
follows from the audience: a broad consumer app cannot ship a reading size
setting that does nothing.

What that means concretely, and what future work must not regress:

- Every text size scales. Both font functions go through
  `Font.custom(_:size:relativeTo:)` against a matched text style, so the
  hierarchy survives the accessibility sizes instead of a caption overtaking a
  heading.
- Layouts reflow rather than clip at the accessibility sizes.
- Every tappable control has a 44 pt hit area, whatever it draws.
- Every icon-only control is labelled.
- Reduce Motion is honoured wherever the app animates.
- Text meets contrast in both appearances. `faint` is decoration-only; anything
  with words in it uses `muted` at 4.5:1 or better on its own page.

Not yet established: a formal WCAG-equivalent audit, VoiceOver rotor support,
and Switch Control testing. Those are undecided rather than claimed.
