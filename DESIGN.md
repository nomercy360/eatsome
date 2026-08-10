---
name: eatsome
description: Say what you ate; the week keeps score in olives.
colors:
  signal-blue: "#2E5BFF"
  signal-blue-dark: "#6E92FF"
  brine-olive: "#7D9455"
  brine-olive-dark: "#9BB374"
  ink: "#0A0F1E"
  ink-dark: "#EDF2F8"
  ink-surface: "#0A0F1E"
  ink-surface-dark: "#E7EDF5"
  on-ink: "#FFFFFF"
  on-ink-dark: "#0A0F1E"
  body: "#4C5F7A"
  body-dark: "#A9B7C8"
  muted: "#667085"
  muted-dark: "#8794A5"
  faint: "#98A2B3"
  faint-dark: "#4A5461"
  background: "#FFFFFF"
  background-dark: "#0B0F16"
  surface: "#FFFFFF"
  surface-dark: "#121820"
  ice: "#F4F7FA"
  ice-dark: "#141A23"
  well: "#F7F9FB"
  well-dark: "#0E141C"
  hairline: "rgba(10, 15, 30, 0.10)"
  hairline-dark: "rgba(255, 255, 255, 0.12)"
  outline: "rgba(10, 15, 30, 0.16)"
  outline-dark: "rgba(255, 255, 255, 0.20)"
  attention: "#C7822F"
  attention-surface: "#FBF3E7"
  danger: "#C24B4B"
  heart: "#E0525B"
typography:
  display:
    fontFamily: "Space Grotesk, -apple-system, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Space Grotesk, -apple-system, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.15
  title:
    fontFamily: "Space Grotesk, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "Space Grotesk, -apple-system, system-ui, sans-serif"
    fontSize: "15.5px"
    fontWeight: 500
    lineHeight: 1.5
  label:
    fontFamily: "IBMPlexMono-Medm, ui-monospace, monospace"
    fontSize: "9.5px"
    fontWeight: 500
    letterSpacing: "0.6px"
rounded:
  chip: "6px"
  control: "8px"
  photo: "8px"
  card: "10px"
spacing:
  screen-inset: "18px"
  card-gap: "14px"
  card-padding: "18px"
components:
  button-primary:
    backgroundColor: "{colors.signal-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.control}"
    padding: "17px 0"
    typography: "{typography.title}"
  button-ink:
    backgroundColor: "{colors.ink-surface}"
    textColor: "{colors.on-ink}"
    rounded: "{rounded.control}"
    padding: "0"
    size: "34px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-padding}"
  card-tinted:
    backgroundColor: "{colors.ice}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-padding}"
  chip:
    backgroundColor: "transparent"
    textColor: "{colors.body}"
    rounded: "{rounded.chip}"
    padding: "6px 10px"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.chip}"
    padding: "9px 14px"
  avatar:
    backgroundColor: "{colors.ice}"
    textColor: "{colors.body}"
    rounded: "{rounded.chip}"
    size: "28px"
---

# Design System: eatsome

## Overview

**Creative North Star: "The Field Notebook"**

A day in eatsome is a record you keep, not a feed you consume. The day page is a
time rail with entries hanging off it, dated and ordered by when the food was
eaten rather than when it was written down — so a day typed up at bedtime still
reads as the day you had, with one small margin note admitting when it was
written. Everything about the surface follows from that: white paper, hairline
rules, measurements set in the margin, and prose reserved for what the app
actually observed.

The system is flat by construction. There is no shadow anywhere in it. Cards are
white on white, separated by a single hairline, because a screen of them should
read as a page of entries rather than a stack of floating objects. Colour is
almost absent: one blue that marks the single thing you are meant to touch, one
olive that belongs to the score and to nothing else, and a warm red spent
entirely on a reaction. Everything else is ink, grey, or paper.

The binding anti-reference is **the calorie tracker**. No ring charts, no macro
donuts, no red/amber/green judgement, no streak flames, no big number in a
circle. The product exists as a rejection of that genre and the surface has to
say so before a word is read. The direction this replaced — rounded SF, 28 pt
radii, ice-blue cards lifted on shadows — is also spent: soft where this system
is exact.

**Key Characteristics:**

- Flat to the point of doctrine; a hairline does every job a shadow would
- Two typefaces with a semantic split, never a decorative one
- Radii live in a 6–10 px band and never become a pill
- One accent, one score colour, one warm colour, and no fourth
- Photographs run to the edge of the screen; the interface recedes around them
- Dark mode is a real appearance, not an inversion

## Colors

A near-monochrome page with three colours allowed on it, each with exactly one
job.

### Primary

- **Signal Blue** (#2E5BFF; #6E92FF in dark): A signal, not a brand colour. It
  marks the one thing on a screen you are meant to touch — the primary button,
  the active selection, an unread badge, a live link. A screen with three blue
  things has no accent.

### Secondary

- **Brine Olive** (#7D9455; #9BB374 in dark): The score, and the colour of the
  fruit itself. It appears in the olive row, in a filled olive reaction, and in
  the confirmed state of a save. It is never a status colour and never means
  "good" on anything that is not an olive.

### Tertiary

- **Heart Red** (#E0525B): The one warm colour in the system, spent entirely on
  a reaction at a table. Nowhere else.

### Neutral

- **Ink** (#0A0F1E; #EDF2F8 in dark): Titles, dish names, anything read first.
- **Ink Surface** (#0A0F1E; #E7EDF5 in dark) with **On Ink** (#FFFFFF; #0A0F1E
  in dark): A matched pair for the one dark object in an exchange. Kept separate
  from Ink because Ink must invert for dark mode as a *text* colour, and a fill
  that inverts with a hardcoded white foreground puts white on white.
- **Body** (#4C5F7A; #A9B7C8 in dark): Running prose, one step back from ink.
- **Muted** (#667085; #8794A5 in dark): Labels, captions, and every mono line.
- **Faint** (#98A2B3; #4A5461 in dark): Chevrons, disabled marks, the "now"
  tick. Never used for text that has to be read.
- **Paper** (#FFFFFF; #0B0F16 in dark) and **Ice** (#F4F7FA; #141A23 in dark):
  The page and the one tinted surface, for heroes and quiet inputs.
- **Hairline** (rgba(10,15,30,.10)) and **Outline** (rgba(10,15,30,.16)): The
  line that does the work shadows used to, and its slightly firmer sibling for a
  control that has an edge but no fill.
- **Attention** (#C7822F) and **Danger** (#C24B4B): A failed reading, a broken
  constraint, a destructive action. Warm amber rather than alarm red for
  anything that is merely *not yet* — the app does not tell people off.

### Named Rules

**The One Signal Rule.** Signal Blue marks the single most touchable thing on a
screen. If two elements are blue, one of them is wrong.

**The Olive Is Not A Status Rule.** Brine Olive belongs to the score. It never
becomes a generic success green, and no other colour ever stands in for an
olive.

**The Matched Pair Rule.** Any fill that inverts between appearances carries its
own foreground token. A hardcoded `white` on an adaptive fill is a bug — it put
white text on a white button and made every sent message invisible in dark mode.

## Typography

**Display Font:** Space Grotesk (400/500/700, bundled; falls back to system)
**Body Font:** Space Grotesk
**Label/Mono Font:** IBM Plex Mono Medium (PostScript name `IBMPlexMono-Medm`)

**Character:** A grotesque with enough personality to carry a headline and
enough neutrality to disappear into a list, paired with a mono that reads as
instrument output rather than as code. The pairing is semantic: the grotesque is
the voice of the app, the mono is the margin of the notebook.

### Hierarchy

- **Display** (700, 32 px, 1.1, −0.02em): The welcome screen and nothing else.
- **Headline** (700, 26 px, 1.15): The question at the top of an onboarding
  step; a dish name on a gallery page.
- **Title** (700, 17 px): Dish names on the timeline, card headings, the primary
  button.
- **Body** (500, 15.5 px, 1.5): Running prose and message text.
- **Label** (mono, 500, 9.5 px, +0.6 tracking, uppercased): Every timestamp,
  count, food-group line, provenance note and staleness stamp.

### Named Rules

**The Margin Rule.** IBM Plex Mono, uppercased, means *this is data about the
thing*. Space Grotesk means *this is the thing*. Mono never carries a sentence;
prose never carries a measurement. `WHOLE GRAINS, FRUIT, NUTS` under "Oatmeal
with pear" is the rule working — the food is the entry, the groups are the
margin.

**The Spelled Number Rule.** Numbers small enough to say out loud are spelled as
words inside a sentence ("Three meals", "four of five") and printed as digits
inside a measure ("4 of 7 days"). A digit mid-sentence reads as data, and the
point of the sentence is that it is not.

## Layout

One column, inset 18 px from the screen edges, with 14 px between cards. Cards
supply 18 px of internal padding; list cards drop to 2 px vertical so their rows
own the rhythm and the dividers run the full width of the inset.

The day page is the exception and the signature: a three-column structure of a
46 px right-aligned time gutter, a 20 px rail carrying a 1 px line and a 7 px
dot, and the entry itself taking the rest. Vertical space between entries is
proportional to elapsed time, clamped to 10–56 px — enough that five hours
between lunch and dinner feels different from twenty minutes between a coffee
and a biscuit, without a literal scale turning an afternoon into a screen and a
half of nothing.

The composer is a bottom safe-area inset on a system material, always present,
never a screen you navigate to.

## Elevation & Depth

**There are no shadows in this system.** Not reduced, not subtle — absent.
Separation is carried entirely by a 1 px hairline at rgba(10,15,30,.10) and by a
single tonal step between paper (#FFFFFF) and ice (#F4F7FA). A white card on a
white page with a hairline edge is the intended reading, and it is what makes a
column of them look like a page of entries rather than a stack of cards.

The only translucency in the app is the system material behind the composer bar,
so content scrolls under it legibly. That is a platform affordance, not a
depth effect.

### Named Rules

**The Flat Page Rule.** No `.shadow()` anywhere. If something needs to separate
from what is behind it, it gets a hairline or a tonal step. If it needs to
separate from *both*, the layout is wrong.

## Shapes

Radii occupy a narrow band and never leave it: chips at 6 px, controls, inputs
and in-card photos at 8 px, cards at 10 px. Nothing is a pill and nothing is a
circle — avatars are squares at the chip radius, and icon buttons are squares at
the control radius.

Photographs are the exception in the other direction: a photo in a feed is
full-bleed with no radius at all, running to both edges of the screen. Inside a
card it squares to 8 px. Passing "am I in a card" is the whole decision; the
radius follows.

### Named Rules

**The No Pill Rule.** No `Capsule()`, no `Circle()` on a control, no
`cornerRadius` above 10. The previous direction ran 12–28 and reads as a
different app.

## Components

### Buttons

- **Shape:** Squared-off, gently eased (8 px continuous radius).
- **Primary:** Signal Blue fill, white label, full width, 17 px vertical
  padding, 17.5 px bold. Disabled drops the fill to Faint.
- **Ink:** The send button and the save action. Ink Surface fill with the On Ink
  foreground — the matched pair, never `white` directly.
- **Quiet:** Label-only in Signal Blue, no fill, no border.
- **Pressed:** 0.985 scale and 0.8 opacity over 120 ms. No shadow, no lift.

### Chips

- **Style:** Outline only — a 1 px hairline at 6 px radius, Body text, no fill.
  Used for a shared ingredient and its weight.
- **State:** Selection is expressed by a filled check or a tinted row, never by
  a chip changing colour.

### Cards / Containers

- **Corner Style:** 10 px continuous.
- **Background:** Surface white, or Ice for the one tinted card per screen.
- **Shadow Strategy:** None. A 1 px hairline stroke on the same radius.
- **Internal Padding:** 18 px; list cards use 18 px horizontal and let rows own
  the vertical.

### Inputs / Fields

- **Style:** Surface fill, 1 px Outline stroke, 6 px radius, 14×9 px padding.
- **Focus:** The stroke becomes Signal Blue at 1.5 px. No glow, no shadow.

### Navigation

- Standard iOS navigation stack with inline titles; the day page is "Today",
  a pushed screen keeps its own name. Sheets for self-contained tasks. No custom
  global navigation and no tab bar — the composer is always on screen, so a tab
  whose job was to open a capture screen had nothing left to do.

### The Olive Row (signature)

Five drawn olives, filled to the score, unfilled at 0.17 opacity. Drawn as
vector ellipses rather than an emoji or a raster asset, so the ghost state is
genuinely the same shape at low opacity and it stays crisp at every size from a
13 px reaction to a 22 px welcome mark. It is the only chart in the app, and it
is deliberately five steps: a rating of 3.4 out of 5 would claim a resolution
nothing in the pipeline has.

### The Time Rail (signature)

A 1 px vertical hairline with a 7 px dot per entry, carrying state by fill:
solid ink for a logged meal, hollow Signal Blue for a reading in progress,
Attention for a failure. It terminates in a hollow Faint tick labelled
`NOW · HH:MM`, because nothing happened at that point yet and the rail should
not run past the day it has not reached.

## Do's and Don'ts

### Do:

- **Do** separate surfaces with the 1 px hairline at rgba(10,15,30,.10) and a
  tonal step from #FFFFFF to #F4F7FA.
- **Do** set every timestamp, count, food-group list and provenance note in
  uppercased IBM Plex Mono at 9.5–10 px with +0.6 tracking.
- **Do** give any adaptive fill its own matched foreground token.
- **Do** keep radii between 6 and 10 px, and square avatars and icon buttons.
- **Do** run photographs full-bleed in a feed and square them to 8 px in a card.
- **Do** state a figure's own limits where it is drawn — `≥` on salt, an `AS OF`
  age on a polled count, "logged 19:02" on a backdated meal.
- **Do** spell small numbers as words in prose and print them as digits in a
  measure.

### Don't:

- **Don't** add a shadow. Anywhere. The system has none by design.
- **Don't** use `Capsule()`, `Circle()` on a control, or a radius above 10 px.
- **Don't** use `.fontDesign(.rounded)` or the system rounded face — it is the
  previous identity and overrides the bundled one on every `Text` that did not
  ask.
- **Don't** put a second blue element on a screen that already has its one
  touchable thing in Signal Blue.
- **Don't** use Brine Olive as a success colour or substitute another colour for
  an olive.
- **Don't** draw a ring chart, macro donut, streak counter, or red/amber/green
  scale. The calorie tracker is the anti-reference.
- **Don't** hardcode `Color.white` as a foreground on any fill that adapts
  between light and dark.
- **Don't** let ink become a second dark object in an exchange — one per
  exchange is what keeps a busy day readable.
