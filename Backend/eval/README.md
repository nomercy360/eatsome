# Eval

Two meals, both real, both with figures somebody else published.

```bash
pnpm eval:nutrition                              # the whole pipeline vs published figures
pnpm eval:nutrition -- --case bibimbap-2026-08-07
tsx eval/composition-recall-poc.ts               # does the model know composition?
tsx eval/macro-mode-poc.ts                       # per 100 g vs the portion total
tsx eval/google-search-poc.ts                    # fetch official figures for branded food
```

## What happened to the old one

46 photos with food-group and weight annotations, scored on recall, precision
and excess rows. Two problems, and the second is fatal:

1. The annotations were model-written, so grading a model against them measured
   agreement with a model.
2. From v21 they graded the wrong thing. The app reports calories, protein,
   carbohydrate, fat and salt; nothing in that set knew any of them.

It is deleted rather than parked, along with the harness that only existed to
serve it. `FINDINGS.md` is kept as a record of what those runs decided — the
model comparison that chose `gemini-3.6-flash` is still the reason it is in
production — but its numbers describe a contract the app no longer ships and
must not be quoted as if they were current.

The text track is parked in the same way; see `golden-text/README.md`.

## What replaced it

`golden/` — meals whose nutrition was published by whoever served them, scored
on the figure a person actually sees. The admission standard is in
`golden/DATASET.md`, and it is deliberately narrow: no case enters without a
number somebody else printed.

`score-nutrition.ts` runs the *production* prompt and the *production* Gemini
schema rather than copies of them, because an eval that asks a different
question than the app is how v16 reported good weights for a month while the app
received none.

Two numbers per case:

- **error against `published`** — weight and composition together, which is what
  a person sees and the only thing worth calling accuracy.
- **Atwater delta** — the model's macronutrients against its own energy figure.
  Needs no ground truth, so it works on any meal.

## What is already known

- Composition alone: **0–3% median error**, 0% when the food is named
  unambiguously (`composition-recall-poc.ts`, 48 sourced rows).
- Asking per-100 g versus asking for the portion total: **a dead heat**, and the
  model's own multiplication was exact on 201 of 201 figures
  (`macro-mode-poc.ts`).
- Weight: **never measured against anything but a model's own annotations.**
  That is the gap this set exists to close, and it is where the error almost
  certainly is.

## Growing it

Two cases is not a calibration set. Add one every time a meal arrives with a
printed number — a chain, a package, a canteen board.
