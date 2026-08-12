# Golden set

Meals whose nutrition was **published by whoever served them** — a canteen
board, a menu, a package panel — photographed as eaten.

That is the entire admission standard, and it is narrower than the set it
replaced on purpose. The previous golden was 46 photos annotated with food
groups and weights, and the annotations were model-written: grading a model
against them measured agreement with a model. Worse, from v21 they graded the
wrong thing. The app no longer reports a food group; it reports calories,
protein, carbohydrate, fat and salt, and nothing in that set knew any of them.

## What a case is

One file per meal, `<id>.json`:

```json
{
  "id": "bibimbap-2026-08-07",
  "photo": "IMG_3263.jpeg",
  "source": "canteen board",
  "published": { "kcal": 670, "protein_g": 24, "carbohydrate_g": 100, "salt_g": 4 },
  "excludes": ["miso soup", "seasoned egg"],
  "items": [{ "label": "white rice", "grams": 250 }]
}
```

- **`published`** is the ground truth and the only thing scored. Every field is
  optional: a board that printed protein alone grades one column, and a meal is
  never scored against a figure nobody published.
- **`excludes`** names what was on the tray but outside the printed figure. Those
  items are subtracted from the app's answer before comparing, because otherwise
  a correct reading of a bigger tray scores as an overestimate. Matching is on
  whole words in order, never substrings — `"steamed white rice".includes("tea")`
  is true, and excluding a cup of tea once silently removed the rice. See
  `../score-nutrition.test.ts`.
- **`items`** is the annotator's read of the photograph — the labels and weights
  a person would expect. It is not scored. It is there to say *where* a wrong
  total came from, since a 30% miss is a different problem when the weight was
  wrong than when the composition was.
- **`photo`** must exist in `../photos/`. A case with no photograph cannot be
  run, only read.
- **`note`** is what a person would say about the tray: what else was on it,
  what the bowl actually held, anything the numbers cannot show. Free text, not
  scored, and the first thing to read when a case starts failing.

## What it is for

Two numbers, per nutrient, per case:

- **error against `published`** — the whole pipeline, weight and composition
  together, which is the number a person actually sees.
- **Atwater delta** of the app's own answer — needs no ground truth at all, and
  catches a garbled composition on any meal, published or not.

Splitting them is the point. Composition was measured separately at 0–3% median
error (`../composition-recall-poc.ts`); weight was never measured against
anything but a model's own annotations. If the totals here are wrong, they are
almost certainly wrong because of the weight, and this set is how that stops
being a guess.

## Growing it

Two meals is not a calibration set. It is the start of one, and the honest thing
to do with a pipeline tuned on two points is not much.

Add a case every time a meal arrives with a printed number. Chains, convenience
food, canteens with boards, anything with a panel. A chain's own figures make the
easiest cases to admit: they are published, they are stable, and recognition is
grounded in search now, so a photographed Big Mac can be scored against the
number McDonald's prints.
