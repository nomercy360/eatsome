---
name: eatsome
description: Say what you ate; the day keeps the count.
colors:
  accent: "#8A97F7"
  on-accent: "#0B0D12"
  protein: "#A3B04A"
  protein-dim: "#2E331F"
  ink: "#EEF1F7"
  body: "#B4BDCC"
  muted: "#737E92"
  faint: "#3A4152"
  background: "#0B0D12"
  surface: "#13161E"
  well: "#10131A"
  raised: "#232834"
  hairline: "#1E2330"
  outline: "#2A3040"
  ink-surface: "#E7EDF5"
  on-ink: "#0B0D12"
  attention: "#E0A257"
  attention-surface: "#2A2113"
  danger: "#E27777"
  heart: "#F4767E"
typography:
  counter:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "58px"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-1.5px"
  display:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "25px"
    fontWeight: 700
    lineHeight: 1.3
  headline:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.3
  title:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Sora, -apple-system, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "1.3px"
    textTransform: "uppercase"
rounded:
  thumb: "14px"
  chip: "16px"
  photo: "16px"
  inner: "20px"
  card: "22px"
  control: "24px"
  hero: "26px"
spacing:
  screen-inset: "20px"
  card-gap: "12px"
  card-padding: "20px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.control}"
    padding: "17px 0"
    typography: "{typography.title}"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.body}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.control}"
    padding: "16px 0"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-padding}"
  card-glass:
    backgroundColor: "rgba(19, 22, 30, 0.72)"
    backdropFilter: "blur(18px)"
    borderColor: "rgba(255, 255, 255, 0.09)"
    rounded: "{rounded.hero}"
    padding: "24px"
  chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.body}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.chip}"
    padding: "10px 16px"
  chip-selected:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.chip}"
    padding: "10px 16px"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    borderColor: "{colors.hairline}"
    focusBorderColor: "{colors.accent}"
    rounded: "{rounded.card}"
    padding: "18px"
  meter-track:
    backgroundColor: "{colors.hairline}"
    height: "6px"
    rounded: "3px"
  day-dot:
    backgroundColor: "{colors.raised}"
    activeBackgroundColor: "{colors.accent}"
    size: "32px"
---

# Design System: eatsome

## Overview

**Creative North Star: "Quiet Night"**

The app is dark, and it is a *ledger you check* rather than a page you read. It
opens on one figure — how many of the last ninety days you wrote something down
— and then on four meters and the meals themselves. Everything else is one tap
off that.

The system is flat by construction. There are no shadows in it. A card is
`#13161E` on a `#0B0D12` page with a 1 px `#1E2330` line around it, which is the
dark-page equivalent of the hairline discipline the previous, light direction
ran on: separation is a line and a tonal step, never a lift. Colour is almost
absent — one periwinkle accent, one olive that belongs to protein, and a warm
amber for anything the app is admitting it does not know.

**This replaced a white, papery, two-typeface system in August 2026** (`9d`,
"The Field Notebook"), and the change is total: page, palette, typeface, radii,
and the home screen's whole premise. The thread — a permanently-present composer
with the day rendered as a conversation — went with it. Screens outside the five
redrawn ones still carry the old *layouts*; they inherit these tokens, because
the tokens are shared, but they have not been redesigned.

**What survived the change**, because it was never a matter of style:

- No score on the food. The olive rating is gone from every redrawn screen. The
  counter measures logging, not eating well.
- Salt is never drawn against a ceiling. It is a floor and it says `≥`.
- A figure that is a range is drawn as a range.
- A total built from part of a plate says how much of it did not answer.

**What changed on purpose.** The old doctrine's binding anti-reference was *the
calorie tracker* — no macro meters, no streaks, no big number. Two of those are
now here, and the reason is that the app can now honestly compute them: energy
and the three macros come off the same sourced composition rows as protein, and
`DailyTargets` derives a personal reference from a complete profile. The
anti-reference narrowed rather than disappeared: no ring charts, no red/amber/
green judgement, no grade for a meal, and no figure the app cannot source.

**Key Characteristics:**

- One scheme, and it is dark. Not an inversion of a light one
- Flat to the point of doctrine; a 1 px line does every job a shadow would
- One typeface, five weights, from an 11 px label to a 58 px counter
- Radii 14–26 px; the previous 6–10 band reads as a table cell on a dark page
- One accent per screen, plus protein's own colour
- Photographs run to the edge and the interface sits on top of them

## Colors

A near-black page with two colours allowed on it, each with exactly one job.

### Primary

- **Periwinkle** (#8A97F7): The accent, at 7.3:1 on the page. It marks the
  primary button, the current selection, and a value that is live right now —
  today's bar in a chart, the caption on a photo being read. A screen with three
  periwinkle things has no accent.

### Secondary

- **Protein Olive** (#A3B04A) and **Protein Dim** (#2E331F): The only nutrient
  with a colour. It gets one because it is the only one of the five with a
  *goal* rather than a reference range, so a protein bar can honestly be full or
  short. Never a generic success green.

### Neutral

- **Ink** (#EEF1F7): Titles, figures, anything read first.
- **Body** (#B4BDCC): Running prose, one step back from ink.
- **Muted** (#737E92): Labels, captions, secondary values, every meta line.
  Three values lighter than the source mock's `#6C7689`, which measures 4.26:1
  here — under the floor for text this size, and it carries real words.
- **Faint** (#3A4152): Chevrons, empty meter track, section labels on a quiet
  row, the denominator of a fraction. 1.6:1 — **decoration and non-text marks
  only**.
- **Background** (#0B0D12), **Surface** (#13161E), **Well** (#10131A),
  **Raised** (#232834): The page, a card on it, an input inset in the card, and
  a raised fill — an unfilled meter, a secondary control, a bar in a chart.
- **Hairline** (#1E2330) and **Outline** (#2A3040): The line that does the work
  shadows used to, and its firmer sibling for a control with an edge and no
  fill. One point, not a half: on a dark page a 0.5 px line at low contrast is
  not there.
- **Ink Surface** (#E7EDF5) with **On Ink** (#0B0D12): A matched pair for
  anything that has to be the one *bright* block on the page.
- **Attention** (#E0A257) and **Danger** (#E27777): An unresolved weight, a
  failed reading, a destructive action. Warm amber for anything that is merely
  *not yet* — the app does not tell people off.

### Named Rules

**The One Accent Rule.** Periwinkle marks the single most touchable or most live
thing on a screen. If two elements are periwinkle, one of them is wrong.

**The Protein Colour Rule.** Olive belongs to protein, because protein has a
goal. It never becomes a success green, and no other nutrient is coloured.

**The Faint Is Not Text Rule.** #3A4152 is 1.6:1 on the page. If a thing has
words in it that have to be read, it does not get this colour. The one argued
exception is a fraction's denominator, which is 42 px and sits against its own
bright numerator.

**The Matched Pair Rule.** Any fill carries its own foreground token. A
hardcoded `white` on a fill is a bug waiting for the fill to change.

## Typography

**One face:** Sora — 400 Regular, 500 Medium, 600 SemiBold, 700 Bold, 800
ExtraBold. Bundled as five static cuts, OFL/SIL, falling back to the system face.

**Character:** A geometric grotesque with a tall x-height and enough width at
800 to hold a 58 px number without looking like a heading that grew. The
two-typeface split it replaced used IBM Plex Mono to mean *this is data about
the thing*; that meaning survives, carried by uppercasing and 1.3 px of tracking
instead of by a second family. One face is what lets a 58 px counter and an
11 px caption on the same screen read as one object.

### Hierarchy

- **Counter** (800, 58 px, −1.5 tracking): The days-logged figure. One per app.
- **Display** (700, 25 px): The question at the top of a sheet — "What did you
  eat?"
- **Headline** (600, 24 px): The meal sentence on the detail card.
- **Title** (700, 16 px): Sheet titles, a meal's name in a row, the primary
  button.
- **Body** (400, 14 px, 1.5): Running prose, captions, meter values.
- **Label** (600, 11 px, +1.3 tracking, uppercased): Section headings, the
  time-and-daypart line, provenance, every timestamp.

### Named Rules

**The Margin Rule.** Uppercased and tracked out means *this is data about the
thing*; sentence case means *this is the thing*. `15:12 · SNACK` above "Salmon
and tuna don" is the rule working — the food is the entry, the stamp is the
margin.

**The Weight Floor Rule.** Nothing readable is set below 11 px, clamped in
`WellieTheme.metaFont` rather than at the call sites, because the previous
system shipped 9–10.5 px meta everywhere and fixing it one caller at a time did
not hold.

**The Spelled Number Rule.** Numbers small enough to say out loud are spelled as
words inside a sentence ("Three meals") and printed as digits inside a measure
("22 / 90"). A digit mid-sentence reads as data, and the point of the sentence
is that it is not.

## Layout

One column, inset 20 px, 12 px between cards, 20 px of card padding. Headers and
prose sit at 22–24 px so a heading is not flush with the card edges below it.

Today is a fixed header — a gear, the date, and `Progress ›` — over a scrolling
column, with the one primary button in a bottom safe-area inset. The counter and
the seven day dots are centred; everything below them is left-aligned. Sheets
carry their own header (`✕ Cancel`, a centred title) rather than a navigation
bar, and the pushed screens hide the system bar and draw a `‹ Today` in the same
position.

The meal detail is the signature exception: the photograph is 360 px tall, runs
to both edges and under the status bar, and the plate card floats on it at
208 px with a translucent fill. It is the only translucent surface in the app,
and the justification is that what is behind it is the plate the card describes.

## Elevation & Depth

**There are no shadows in this system.** Not reduced — absent. Separation is a
1 px `#1E2330` line plus one tonal step from `#0B0D12` to `#13161E`. Depth on a
dark page comes from the step, and a card that needed more than that would be a
layout problem.

The translucent plate card is the single exception, and it is a *content*
effect: the photo shows through it.

### Named Rules

**The Flat Page Rule.** No `.shadow()` anywhere. If something needs to separate
from what is behind it, it gets a line or a tonal step.

## Shapes

Radii run 14–26 px. A thumbnail is 14, a chip and an in-card photo 16, an inner
control 20, a card 22, the primary button 24, and a hero card 26. The day dots
and the two round icon buttons in the composer are genuine circles — the only
circles in the system, and both are 32–44 px marks rather than containers.

Photographs are full-bleed with no radius when they are the page, and square to
16 px inside a card. Passing "am I in a card" is the whole decision.

### Named Rules

**The Big Radius Rule.** Nothing below 14 px. The previous direction ran 6–10
and reads as a different app — on a dark page a 10 px corner with a low-contrast
edge reads as a table cell rather than as an object.

## Components

### Buttons

- **Primary:** Accent fill, page-coloured label, full width, 17 px vertical
  padding, 16.5 px bold, 24 px radius. Disabled drops to Raised with Muted text.
- **Secondary:** Surface fill, 1 px hairline, Body label. "Log another while
  this runs", "From gallery" / "Camera".
- **Quiet:** Label-only in Muted, no fill, no border.
- **Pressed:** 0.985 scale and 0.82 opacity over 120 ms. No lift.

### Chips

- **Unselected:** Surface fill, 1 px hairline, 16 px radius, Body semibold.
- **Selected:** Accent fill, page-coloured bold label, no border.
- Used for the day window on Progress, the share question on a meal, and the
  repeat-dish row in the composer. `WellieChipRow` is the segmented form — chips
  with a gap, never a `Picker`, whose segmented style paints its own chrome.

### Cards / Containers

- **Corner style:** 22 px continuous; 26 px for a hero.
- **Background:** Surface, with a 1 px hairline stroke on the same radius.
- **Shadow strategy:** None.
- **Internal padding:** 20 px; list cards let their rows own the vertical.

### Inputs / Fields

- **Style:** Surface fill, 1 px hairline, 22 px radius, 18 px padding.
- **Focus:** The stroke becomes Accent at 1.5 px, eased over 150 ms. No glow.
- The composer puts the mic and send buttons on their own row *under* the field,
  as 44 px circles, so the sentence gets the full width.

### Meters (signature)

A 6 px track at Hairline with a 3 px radius, filling to the day's value on
appear. Two forms, because `DailyTargets` publishes two kinds of reference:

- **Point** — energy and protein have a number, so the label reads `412 / 1,800
  kcal` and the fill is a fraction of it.
- **Band** — carbohydrate and fat have an AMDR *range*, which the model
  deliberately declines to collapse into a point. A lighter Raised stretch marks
  the range on the track and the label reads `172 / 202–292 g`.

The track is scaled to `max(reference, value)`, so a day past its reference is
drawn past it with a 2 px notch at the reference. A bar pinned at 100 % would
make 3,000 kcal and 1,800 kcal look like the same day.

### Bar series (signature)

One bar per day, scaled to the tallest in the window, gap narrowing from 5 px to
1.5 px as the window grows from 14 to 90 days. A day with nothing logged draws
*nothing* — a gap in the record and a day you ate nothing are different facts.
A logged day always draws at least 3 px, so a 40 kcal coffee is still visible
against a 2,600 kcal peak.

### The day strip (signature)

Seven 32 px circles ending today, each carrying a weekday initial. Filled Accent
when something was logged, Raised when nothing was, and — for today only, before
anything is logged — an Accent outline rather than an empty dot, because the day
is not a gap yet.

## Do's and Don'ts

### Do:

- **Do** separate surfaces with the 1 px `#1E2330` line and the step from
  `#0B0D12` to `#13161E`.
- **Do** set section headings, timestamps and provenance in Sora 600 at 11 px,
  uppercased, with 1.3 px tracking.
- **Do** keep radii between 14 and 26 px.
- **Do** draw a range as a range when the source publishes one.
- **Do** state a figure's own limits where it is drawn — `≥` on salt, "9 g
  today wasn't recognised" under a partial total, "averaged over the 10 days you
  logged" under a mean.
- **Do** run photographs full-bleed when they are the subject and square them to
  16 px in a card.

### Don't:

- **Don't** add a shadow. Anywhere.
- **Don't** put salt on a meter, or beside a daily ceiling. It is a floor.
- **Don't** invent a single target for carbohydrate or fat.
- **Don't** use `#3A4152` for text that has to be read.
- **Don't** put a second accent-coloured element on a screen that already has
  its one live thing.
- **Don't** use protein olive as a success colour, or colour a second nutrient.
- **Don't** draw a ring chart, a macro donut, a red/amber/green scale, or any
  grade for a meal. The calorie tracker is still the anti-reference; what
  changed is that sourced totals are no longer part of what it means.
- **Don't** add a light appearance. Every ratio here is measured against
  `#0B0D12`, and the app pins `preferredColorScheme(.dark)`.
- **Don't** use `.fontDesign(.rounded)` or the system face — the bundled one is
  set per call by `WellieTheme.font`, and a design modifier fights it on every
  `Text` that did not ask.
