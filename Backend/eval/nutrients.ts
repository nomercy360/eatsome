import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * How wrong the food table is, against meals whose figures were printed.
 *
 *   pnpm eval:nutrients
 *
 * Protein was the one macro the app totalled, and until this existed the table
 * was tuned by argument: a row was changed because a figure "looked low", and
 * nothing said whether the change helped. Two measured meals already caught a
 * regression that reasoning had missed — resolving `pork` to lean roast loin at
 * 28.6 g/100 g is right for that food and wrong for thin sauced bulgogi, and it
 * moved a bowl from 24 g to 35.6 g against a published 24.
 *
 * It now grades energy, carbohydrate, fat and salt on the same terms, because
 * they are now derived on the same terms: one source row per food, chosen by
 * label and weighed by grams. A canteen board that prints four figures grades
 * four columns; one that prints protein alone grades one. A meal is never
 * scored against a figure nobody published.
 *
 * Two numbers per nutrient, because they answer different questions:
 *
 *   food  what the app derives, food table first and group table behind it
 *   group what it would derive with no food table at all
 *
 * A change that improves `food` and leaves `group` alone is a table change. A
 * change that moves both is a weight change and belongs in the golden set.
 *
 * What this measured, on the first run
 * ------------------------------------
 * Energy came out at 1% on the one meal that printed it, and protein improved
 * from 33% to 20% with the food table in front. Salt came out at MINUS 82%, and
 * that is not noise — it is structural, and the reason `Nutrients.saltGrams` is
 * presented as a floor rather than a measurement.
 *
 * Composition tables publish plain preparations. Cooked white rice is 1 mg of
 * sodium per 100 g, and a canteen bibimbap is 4 g of salt, because the salt is
 * in the gochujang and the soy and the seasoning — none of which is an
 * ingredient a model reports, and none of which has a weight on the plate. The
 * derived figure is therefore a genuine lower bound on salt and never an
 * estimate of it, and no screen may compare it to the 5 g ceiling as though it
 * were one. A salt figure that reads "well under" on a 4 g lunch is the
 * partial-total failure this app has refused to ship everywhere else.
 *
 * Carbohydrate ran 19% low on the same meal for a milder version of the same
 * reason: sauce and sugar are real and not on the ingredient list.
 */
type Nutrients = {
  protein: number;
  fat: number;
  carbohydrate: number;
  kcal: number;
  sodium: number;
};

type Labelled = {
  meals: Array<{
    id: string;
    photo: string;
    source: string;
    published: {
      protein_g?: number;
      calories_kcal?: number;
      carbohydrate_g?: number;
      fat_g?: number;
      salt_g?: number;
    };
    excludes?: string[];
    items: Array<{ group: string; label: string; grams: number }>;
  }>;
};

type Food = { per100g: Nutrients; source: string; basis: string; name: string };

const root = import.meta.dirname;
const labelled = JSON.parse(readFileSync(join(root, "labelled.json"), "utf8")) as Labelled;
const config = JSON.parse(
  readFileSync(join(root, "../../Core/Sources/ShamanCore/Resources/shaman-config.json"), "utf8"),
) as {
  nutrientsPerGram?: {
    version: string;
    groups: Record<string, Food>;
    foods: Record<string, Food>;
  };
};

if (!config.nutrientsPerGram) {
  console.error("no nutrientsPerGram in shaman-config.json — run scripts/build-food-table.py");
  process.exit(1);
}
const { foods, groups } = config.nutrientsPerGram;

/** Mirrors `ServingWeight.defaultGrams`. */
const SERVING_G: Record<string, number> = {
  fish: 100,
  white_meat: 100,
  red_meat: 100,
  processed_meat: 50,
  egg: 50,
  dairy: 200,
  legumes: 150,
  nuts: 30,
  whole_grains: 150,
  refined_grains: 150,
  vegetables: 100,
  fruit: 120,
  healthy_fats: 30,
  pastry: 60,
  sweets: 30,
  sofrito: 50,
  butter: 15,
  olive_oil: 10,
  sugary_drinks: 330,
  coffee: 200,
  tea: 200,
  juice: 200,
  plant_milk: 200,
  smoothie: 250,
  alcohol: 330,
  other: 100,
};

/**
 * Mirrors `Protein.defaultGramsPerServing`, and exists for protein alone.
 *
 * The other four fall back to `nutrientsPerGram.groups` in the client, because
 * there is no hand-calibrated per-serving table for them and never was. Protein
 * keeps this one because every protein figure in the app's history was scored
 * against it; see the note on `Nutrition`.
 */
const PROTEIN_PER_SERVING: Record<string, number> = {
  fish: 22,
  white_meat: 26,
  red_meat: 24,
  processed_meat: 14,
  egg: 6,
  dairy: 8,
  legumes: 8,
  nuts: 5,
  whole_grains: 4,
  refined_grains: 3,
  vegetables: 2,
  fruit: 0.5,
  healthy_fats: 1.5,
  pastry: 4,
  sweets: 2,
  sofrito: 1,
  butter: 0.5,
  olive_oil: 0,
  sugary_drinks: 0,
  alcohol: 0,
  coffee: 0,
  tea: 0,
  juice: 1,
  plant_milk: 3,
  smoothie: 2,
  other: 0,
};

/** Must agree with `Nutrients.saltPerSodium` in Core. */
const SALT_PER_SODIUM = 58.44 / 22.99;

/** Must agree with `FoodLabel.candidates` in Core and `normalise` in the build script. */
function candidates(label: string): string[] {
  const normalise = (value: string) =>
    value
      .split("")
      .map((c) => (/[\p{L}\p{N}\s]/u.test(c) ? c.toLowerCase() : " "))
      .join("")
      .split(/\s+/)
      .filter(Boolean)
      .join(" ");
  const out: string[] = [];
  const add = (value: string) => {
    if (value && !out.includes(value)) out.push(value);
  };
  add(normalise(label));
  if (label.includes("(")) add(normalise(label.split("(")[0] ?? ""));
  if (out[0]?.endsWith("s")) add(out[0].slice(0, -1));
  return out;
}

function lookup(group: string, label: string): Food | undefined {
  for (const candidate of candidates(label)) {
    const hit = foods[`${group}|${candidate}`];
    if (hit) return hit;
  }
  return undefined;
}

const ZERO: Nutrients = { protein: 0, fat: 0, carbohydrate: 0, kcal: 0, sodium: 0 };

function scale(per100g: Nutrients, grams: number): Nutrients {
  const f = grams / 100;
  return {
    protein: per100g.protein * f,
    fat: per100g.fat * f,
    carbohydrate: per100g.carbohydrate * f,
    kcal: per100g.kcal * f,
    sodium: per100g.sodium * f,
  };
}

function add(a: Nutrients, b: Nutrients): Nutrients {
  return {
    protein: a.protein + b.protein,
    fat: a.fat + b.fat,
    carbohydrate: a.carbohydrate + b.carbohydrate,
    kcal: a.kcal + b.kcal,
    sodium: a.sodium + b.sodium,
  };
}

/** The client's group fallback: protein from its own table, the rest from the group row. */
function byGroup(group: string, grams: number): Nutrients {
  const protein = (grams / (SERVING_G[group] ?? 100)) * (PROTEIN_PER_SERVING[group] ?? 0);
  const representative = groups[group];
  const rest = representative ? scale(representative.per100g, grams) : ZERO;
  return { ...rest, protein };
}

/** The five published names, and how to read each out of a derived total. */
const COLUMNS = [
  { key: "protein_g", label: "protein", unit: "g", read: (n: Nutrients) => n.protein },
  { key: "calories_kcal", label: "energy", unit: "kcal", read: (n: Nutrients) => n.kcal },
  { key: "carbohydrate_g", label: "carbs", unit: "g", read: (n: Nutrients) => n.carbohydrate },
  { key: "fat_g", label: "fat", unit: "g", read: (n: Nutrients) => n.fat },
  {
    key: "salt_g",
    label: "salt",
    unit: "g",
    read: (n: Nutrients) => (n.sodium * SALT_PER_SODIUM) / 1000,
  },
] as const;

console.log(`# Food table\n`);
console.log(
  `Table \`${config.nutrientsPerGram.version}\`, ` +
    `${Object.keys(foods).length} foods and ${Object.keys(groups).length} group rows.\n`,
);
console.log(`Graded against meals whose figures were published. Both columns are derived from`);
console.log(`the same annotated weights, so the difference between them is the table alone.`);
console.log(`A nutrient nobody printed for a meal is not scored for that meal.\n`);
console.log(`| meal | nutrient | published | food table | group table | food err | group err |`);
console.log(`| --- | --- | --- | --- | --- | --- | --- |`);

const errors = new Map<string, { food: number[]; group: number[] }>();
const detail: string[] = [];
const pct = (value: number) => `${value >= 0 ? "+" : ""}${(value * 100).toFixed(0)}%`;

for (const meal of labelled.meals) {
  let withFood = ZERO;
  let withGroup = ZERO;
  const lines: string[] = [];
  for (const item of meal.items) {
    const hit = lookup(item.group, item.label);
    const fromGroup = byGroup(item.group, item.grams);
    const fromFood = hit ? scale(hit.per100g, item.grams) : fromGroup;
    withFood = add(withFood, fromFood);
    withGroup = add(withGroup, fromGroup);
    lines.push(
      `  ${item.label.padEnd(16)} ${String(item.grams).padStart(4)} g  ` +
        `${fromFood.kcal.toFixed(0).padStart(4)} kcal  ` +
        `${fromFood.protein.toFixed(1).padStart(5)} g protein  ` +
        `${hit ? hit.source : "group table"}${hit ? `  ${hit.name.slice(0, 40)}` : ""}`,
    );
  }

  for (const column of COLUMNS) {
    const want = meal.published[column.key];
    if (want === undefined) continue;
    const food = column.read(withFood);
    const group = column.read(withGroup);
    const fErr = (food - want) / want;
    const gErr = (group - want) / want;
    const bucket = errors.get(column.label) ?? { food: [], group: [] };
    bucket.food.push(Math.abs(fErr));
    bucket.group.push(Math.abs(gErr));
    errors.set(column.label, bucket);
    const round = (value: number) => (column.unit === "kcal" ? value.toFixed(0) : value.toFixed(1));
    console.log(
      `| ${meal.id} | ${column.label} | ${want} ${column.unit} | ${round(food)} ${column.unit} | ` +
        `${round(group)} ${column.unit} | **${pct(fErr)}** | ${pct(gErr)} |`,
    );
  }

  detail.push(
    `\n**${meal.id}** (${meal.source}${meal.excludes ? `, excludes ${meal.excludes.join(", ")}` : ""})`,
  );
  detail.push(...lines);
}

console.log(`\n## Mean absolute error\n`);
console.log(`| nutrient | meals | food table | group table |`);
console.log(`| --- | --- | --- | --- |`);
const mean = (values: number[]) => values.reduce((a, b) => a + b, 0) / values.length;
for (const column of COLUMNS) {
  const bucket = errors.get(column.label);
  if (!bucket?.food.length) continue;
  console.log(
    `| ${column.label} | ${bucket.food.length} | ` +
      `**${(mean(bucket.food) * 100).toFixed(0)}%** | ${(mean(bucket.group) * 100).toFixed(0)}% |`,
  );
}

const scored = [...errors.values()].reduce((n, b) => n + b.food.length, 0);
console.log(
  `\n${labelled.meals.length} meals and ${scored} published figures is not a calibration set.\n` +
    `Treat a change that moves this by less than the spread between meals as noise, and add\n` +
    `a meal every time one arrives with a printed number. Energy and carbohydrate are the\n` +
    `thinnest columns here and the ones a canteen board is most likely to print, so they are\n` +
    `the cheapest to widen.`,
);
console.log(`\n## Per item\n${detail.join("\n")}`);
