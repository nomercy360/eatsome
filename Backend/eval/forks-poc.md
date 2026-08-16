# forks-poc — how should the model report a choice it cannot make?

`gemini-3.7-flash`, `thinkingLevel: low`, search on, production prompt v27
with only the `sizes` section swapped. 14 cases (9 text, 5 photos), 2 runs
each, 2026-08-16. Raw answers in `runs/forks-poc-2026-08-16T12-3*.json`;
harness is `forks-poc.ts`.

## Conditions

| cond       | wire shape                                                                            |
|------------|----------------------------------------------------------------------------------------|
| `sizes`    | what ships: `sizes[{label,grams,per_100g,basis}]` on branded rows + `alternatives`     |
| `forks`    | `forks[{axis, options[{label,grams,per_100g,basis,chosen}]}]` replacing `sizes`; any axis, any row |
| `question` | as `forks`, plus model-written `question` prose per fork                               |
| `evidence` | as `forks`, plus `chosen_from: stated \| seen \| assumed` per fork (8 cases, 2 runs)   |

## What happened

**The generic shape works and the model fills it honestly.** Every fork in every
run had exactly one `chosen` option, and that option agreed with the row's own
grams and kcal within 10% (26/26 forks, 29/29 question, 26/26 evidence). Options
pass the Atwater check bar the zero-calorie colas (1–3 kcal, macros 0 — noise).
Base-row accuracy did not move: Subway JP clubhouse 698–700 in 11 of 12 runs,
gyudon 632–634, chipotle 973–1012, Starbucks tall latte 234, across all shapes.

**Axes beyond size appear, and they are the ones `sizes` cannot say:**

- Big Mac meal (text and photo): `drink[Coca-Cola* 220, Diet Coke 0, Sprite 210]`
  — Δ135–220 kcal, invisible to a size ladder; the photo has an opaque cup.
- Starbucks latte: `milk[whole* 234, low-fat 188, non-fat 143, oat 207]` Δ91;
  once `temperature[hot* 235, iced 126]` Δ109.
- Fries and drink each get their own size fork on the same row set.

**Nothing on a home plate or canteen tray forked** — lentil soup, caesar,
bibimbap photo, mentaiko photo: 0 forks in 24 runs. Chipotle burrito
(one size) : 0 forks in 6 runs. A cafe cappuccino forked on milk (Δ18–63) and
size (Δ43–99), which is why the app needs an absolute floor and not only a
ratio: those are half the drink and not worth a tap in a day.

**The failure the plain `forks` shape has: it forks on what the input already
settled.** "grande oat milk latte" still got a size fork in 3 of 4 runs
(chosen = Grande, correct, but a redundant question). "subway … footlong" got
Regular offered every time. The 6-inch Subway photo and the Grande cup photo
each got the other sizes even though the size is legible. Prompting "no fork on
anything settled" did not stop it at low thinking.

**`chosen_from` fixes that, 16/16.** In the `evidence` condition the model
labelled the footlong and the grande-oat forks `stated`, the 6-inch wrapper,
the Grande cup and the visibly small fries `seen`, and the latte size/milk,
the drink in the opaque cup and the cappuccino `assumed`. Not one wrong. That
is the flag the app gates on: only an `assumed` fork is a question; a `stated`
or `seen` fork is kept as priced options for the pick sheet and nothing more.

**Model-written `question` prose bought nothing.** It came out generic ("Which
size did you have?", "Which milk was used?") — exactly what a template writes,
in the model's language rather than the phone's, at +5% output tokens. One
`question` run also priced the US All-American Club (900) instead of the JP
clubhouse (698); one run in six is drift, not the field, but there is no upside
to trade against it. Drop it.

**Cost:** forks vs sizes, +11% latency (7.5 s vs 6.7 s), +13% output tokens.
`evidence` +22% latency on a harder-skewed subset. Acceptable.

**Schema note:** Gemini 400s when both `forks` and its nested `options` array
carry `maxItems`; either alone is fine. Bound the inner one in the prompt.

## Recommendation

Ship `forks` with `chosen_from`, replacing `sizes`; keep `alternatives`.
Per fork: `axis` (free short text, rendered not branched on), `chosen_from`,
`options[{label, grams, per_100g, basis, chosen}]`. The app asks only when
`chosen_from == assumed` **and** the kcal spread across options ≥ max(100 kcal,
20% of the row) — that keeps gyudon (Δ350–540), Subway (Δ350), fries (Δ250),
the drink in the cup (Δ135–220), latte size (Δ141–243), and drops cappuccino
milk (Δ18–63) and latte milk (Δ91). One fork shown at a time, largest Δ first.
The question is a template over `axis` and Δ; the model never writes it.

Prompt line to keep from v27 that the fork prompt lost: option labels in the
market's own words — `sizes` gave 並盛 / フットロング, `forks` gave "Regular (並盛)".

## Shipped (2026-08-16, prompt `meal-v28-2026-08-16`)

`forks` with `chosen_from` replaced `sizes`; `alternatives` stayed. The one
thing the live smoke added: once in five the model returned a fork with *no*
option chosen (a cappuccino's milk). The Worker settles that by arithmetic —
`settleForks` in `contracts.ts` marks the option whose whole-row energy is
nearest the row's, or drops the fork if none is within tolerance — rather than
refusing the meal. The stored form is still held to exactly one chosen.
