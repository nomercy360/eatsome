---
name: eatsome
description: Photograph it or say what it was. We work out the numbers.
colors:
  accent: "#C6E82C"
  on-accent: "#151820"
  ink: "#151820"
  body: "#5B616D"
  muted: "#666C77"
  faint: "#858B96"
  background: "#FAFAF8"
  surface: "#FFFFFF"
  well: "#F3F1EB"
  raised: "#E7E4DC"
  hairline: "#ECEAE4"
  outline: "#DDDAD2"
  navigation: "#151820"
  protein: "#6D7900"
  attention: "#8F6212"
  danger: "#BB3B37"
typography:
  family: "General Sans, -apple-system, system-ui, sans-serif"
  figures: "Space Grotesk, ui-monospace, sans-serif"
  display: "700 22px/1.1 General Sans; -0.5px tracking"
  figure: "700 42px/1 Space Grotesk; -1.5px tracking"
  title: "700 16px/1.2 General Sans"
  body: "400 14px/1.45 General Sans"
  meta: "600 11px/1.2 General Sans; uppercase; 1.3px tracking"
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
---

# Design system: eatsome

## Direction

**Creative north star: the living food ledger.**

Eatsome should feel like a quiet paper ledger that happens to understand a
photograph or a sentence. Warm off-white pages, white grouped cards, near-black
ink, and one electric-lime signal create the world. The design rejects generic
dashboard chrome: the day, the meal, and the reader's own reference are the
content; controls stay compact and secondary.

The primary story is always legible in order: describe or photograph a meal,
watch it being read, correct what is wrong, save it, then review today or an
earlier day. Every one of the 26 approved states belongs to that story.

## Appearance

The app follows the device appearance. It never calls `preferredColorScheme`.
Light is the authored warm-paper palette above. Dark keeps the same hierarchy
with `#0B0D12` page, `#13161E` cards, `#EEF1F7` ink, and the same lime action.
The navigation capsule stays near-black in both appearances so its meaning and
the central lime action do not move when the system switches themes.

These are two expressions of one system, not separately styled screens. Every
semantic color is an adaptive token in `WellieTheme`; view code does not branch
on the color scheme.

## Color rules

- Lime is an action, a current selection, or a soft glow behind a live energy
  value. It is never paragraph text and always carries near-black foreground.
- Near-black is the stable navigation object and the selected calendar day.
- White cards separate from the warm page with a one-point hairline, not a
  drop shadow. Glow is reserved for the live figure and primary action.
- Protein may use its darker olive token when it needs readable text. Carbs
  and fat use their nutrient icons, not new semantic status colors.
- Muted text must remain readable in either appearance. `faint` is decoration,
  disabled affordance, or a secondary denominator—not essential copy.
- Amber means unresolved or incomplete; red means failure or destruction.

## Type

Two families, split by what the text *is*. General Sans (400–700) carries
words: titles, labels, sentences, buttons. Space Grotesk (400–700) carries
figures: an energy total, a weight, a time, a count, a fraction — anything a
reader scans for the number rather than reads. A sentence that happens to
contain a number stays in General Sans. Bold display type makes short
questions and meal names feel direct; body copy remains small and plain.
Uppercase plus tracking marks metadata such as `THE DAY`, dates, and section
names — that is a style, not a third face.

Use the large 42-point figure only for the current energy total. Screen and
sheet titles are generally 16 points; questions may rise to 25–30 points. Keep
line lengths short and let labels scale before allowing figures to collide.

## Shape and layout

- Standard screen inset: 20 points.
- Cards: 22-point continuous radius with a one-point hairline.
- Controls: 24-point radius; chips: 16 points; photos: 16 points.
- Group related rows into one card with internal dividers. Avoid a separate
  rounded rectangle for every fact.
- The main navigation is one near-black capsule with four marks; the central
  lime plus is the only raised action.
- Photo-backed meal details run the image to the top edge and float one
  translucent summary card over it. Typed meals remain warm and typographic.
- Calendar days are filled cells: warm neutral for no log, pale lime for light
  intake, vivid lime near the reference, and near-black for selection.

## Interaction and truthfulness

Primary buttons use lime, near-black copy, and a restrained lime glow. Disabled
buttons remain visible in the well color with readable muted copy. Minimum hit
targets stay 44 points even when the visible mark is smaller.

Progress reports only data that exists. Salt has no invented ceiling. Protein
is compared only when a personal goal is available. Empty days say they are
empty. Loading, failure, correction, and saved states remain explicit rather
than being replaced with optimistic placeholder content.

The system keeps native platform behavior for permissions, Apple sign-in,
keyboard entry, sheets, swipe-to-delete, VoiceOver, Dynamic Type, and Reduce
Motion. Visual styling must not turn a real system action into a decorative
replica.

## Screen families

- **Entry:** sign in; Start with Health; goal, equation, age, height, weight,
  activity; daily reference.
- **Daily ledger:** Today empty and populated; progress; Earlier days; You;
  Body & activity.
- **Capture:** log composer; reading photo; reading words; reading failed.
- **Meal:** recognized detail; disambiguation; correction in words; saved photo
  meal; saved typed meal; note editor.

All families share the same tokens and navigation language. A new screen should
look like another page from this ledger, not another product bolted onto it.
