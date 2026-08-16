import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.7-flash";
const RUNS = 2;

/**
 * Does it matter who does the multiplication?
 *
 *   ./node_modules/.bin/tsx eval/macro-mode-poc.ts
 *
 * Three ways of asking the same model for the same meal's nutrition:
 *
 *   per100g    model returns composition per 100 g; WE multiply by the weight
 *   absolute   model returns the figures for the stated weight; IT multiplies
 *   both       model returns both in one answer, which is the only way to see
 *              its arithmetic error on its own composition belief
 *
 * Items are real (kind, label, grams) triples from the remote `recognitions`
 * table, restricted to labels that resolve exactly to a sourced table row — so
 * the published per-100 g figure and the weight together give a ground truth
 * for the absolute answer. That inherits the assumption that the table row is
 * right for the label, which is the same assumption `eval:nutrients` makes.
 *
 * Two runs per condition, because a difference smaller than run-to-run drift is
 * not a difference.
 */

type Nutrients = {
  protein: number;
  fat: number;
  carbohydrate: number;
  kcal: number;
  sodium: number;
};
type Item = { kind: string; label: string; grams: number; truth: Nutrients; row: string };

const NUTRIENTS: Array<keyof Nutrients> = ["kcal", "protein", "fat", "carbohydrate", "sodium"];
type Mode = "per100g" | "absolute" | "both";

const PROMPTS: Record<Mode, string> = {
  per100g: `You report nutrient composition for named foods.

For each item return composition PER 100 g of edible portion: protein, fat and carbohydrate in grams, energy in kilocalories, sodium in milligrams. Never per serving, and never for the stated weight — the weight is context for identifying the food, not the basis of your answer.

Answer from what published food composition tables report.`,
  absolute: `You report the nutrients present in a weighed portion of food.

Each item gives a food and the weight of it present. Return the nutrients IN THAT WEIGHT: protein, fat and carbohydrate in grams, energy in kilocalories, sodium in milligrams. Not per 100 g — the totals for the weight given.

Answer from what published food composition tables report.`,
  both: `You report nutrient composition for weighed foods, two ways.

For each item return BOTH: composition per 100 g of edible portion, and the nutrients present in the stated weight. Protein, fat and carbohydrate in grams, energy in kilocalories, sodium in milligrams, in both blocks.

Answer from what published food composition tables report.`,
};

function nutrientBlock(description: string) {
  return {
    type: "OBJECT",
    propertyOrdering: ["protein", "fat", "carbohydrate", "kcal", "sodium"],
    required: ["protein", "fat", "carbohydrate", "kcal", "sodium"],
    description,
    properties: {
      protein: { type: "NUMBER" },
      fat: { type: "NUMBER" },
      carbohydrate: { type: "NUMBER" },
      kcal: { type: "NUMBER" },
      sodium: { type: "NUMBER", description: "milligrams" },
    },
  };
}

function schemaFor(mode: Mode) {
  const properties: Record<string, unknown> = { index: { type: "INTEGER" } };
  const order = ["index"];
  if (mode !== "absolute") {
    properties.per100g = nutrientBlock("Per 100 g of edible portion.");
    order.push("per100g");
  }
  if (mode !== "per100g") {
    properties.inPortion = nutrientBlock("Present in the stated weight.");
    order.push("inPortion");
  }
  return {
    type: "OBJECT",
    propertyOrdering: ["items"],
    required: ["items"],
    properties: {
      items: {
        type: "ARRAY",
        items: { type: "OBJECT", propertyOrdering: order, required: order, properties },
      },
    },
  };
}

function loadApiKey(): string {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

type Reply = { index: number; per100g?: Nutrients; inPortion?: Nutrients };

async function ask(apiKey: string, mode: Mode, items: Item[]): Promise<Reply[]> {
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(MODEL)}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: PROMPTS[mode] }] },
      contents: [
        {
          role: "user",
          parts: [
            {
              text: JSON.stringify({
                items: items.map((item, index) => ({
                  index,
                  food: item.label,
                  kind: item.kind,
                  weight_g: item.grams,
                })),
              }),
            },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schemaFor(mode),
        thinkingConfig: { thinkingLevel: "low" },
      },
    }),
  });
  const body = (await response.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string; thought?: boolean }> } }>;
    error?: { message?: string };
  };
  if (!response.ok)
    throw new Error(`Gemini ${response.status}: ${body.error?.message ?? "no body"}`);
  const raw = (body.candidates?.[0]?.content?.parts ?? [])
    .filter((part) => part.thought !== true)
    .map((part) => part.text ?? "")
    .join("");
  return (JSON.parse(raw) as { items: Reply[] }).items;
}

const median = (values: number[]): number => {
  if (!values.length) return Number.NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

const atwater = (n: Nutrients): number | null =>
  n.kcal > 0 ? Math.abs(n.protein * 4 + n.carbohydrate * 4 + n.fat * 9 - n.kcal) / n.kcal : null;

const items = JSON.parse(
  readFileSync(join(import.meta.dirname, "macro-mode-items.json"), "utf8"),
) as Item[];
const apiKey = loadApiKey();

console.log(`Macro mode POC — ${MODEL}, ${items.length} weighed items, ${RUNS} runs per mode`);
console.log("Ground truth: published per-100 g row x the recognised weight.\n");

// error of the ABSOLUTE figure against the published absolute, per mode.
const perMode = new Map<Mode, Map<keyof Nutrients, number[]>>();
const atwaterByMode = new Map<Mode, number[]>();
const arithmetic: number[] = [];
const worstArithmetic: Array<{ label: string; nutrient: string; said: number; implied: number }> =
  [];
// paired per-item medians, so per100g and absolute can be compared item by item.
const paired = new Map<string, { per100g: number[]; absolute: number[] }>();

for (const mode of ["per100g", "absolute", "both"] as Mode[]) {
  const errors = new Map<keyof Nutrients, number[]>(NUTRIENTS.map((key) => [key, []]));
  const deltas: number[] = [];
  for (let run = 0; run < RUNS; run += 1) {
    const replies = await ask(apiKey, mode, items);
    const byIndex = new Map(replies.map((reply) => [reply.index, reply]));
    for (const [index, item] of items.entries()) {
      const reply = byIndex.get(index);
      if (!reply) continue;
      const scale = item.grams / 100;
      const absolute =
        reply.inPortion ??
        (reply.per100g
          ? (Object.fromEntries(
              NUTRIENTS.map((key) => [key, reply.per100g![key] * scale]),
            ) as Nutrients)
          : null);
      if (!absolute) continue;

      if (mode === "both" && reply.per100g && reply.inPortion) {
        for (const nutrient of NUTRIENTS) {
          const implied = reply.per100g[nutrient] * scale;
          if (implied < 0.5) continue;
          const err = Math.abs(reply.inPortion[nutrient] - implied) / implied;
          arithmetic.push(err);
          if (err > 0.02) {
            worstArithmetic.push({
              label: item.label,
              nutrient,
              said: reply.inPortion[nutrient],
              implied: Number(implied.toFixed(2)),
            });
          }
        }
      }

      const delta = atwater(absolute);
      if (delta !== null) deltas.push(delta);

      for (const nutrient of NUTRIENTS) {
        const want = item.truth[nutrient] * scale;
        if (want < 1) continue;
        const err = Math.abs(absolute[nutrient] - want) / want;
        errors.get(nutrient)?.push(err);
        if (mode === "per100g" || mode === "absolute") {
          const key = `${item.label}|${nutrient}`;
          const entry = paired.get(key) ?? { per100g: [], absolute: [] };
          entry[mode as "per100g" | "absolute"].push(err);
          paired.set(key, entry);
        }
      }
    }
  }
  perMode.set(mode, errors);
  atwaterByMode.set(mode, deltas);
}

console.log("median error of the ABSOLUTE figure vs the published one:\n");
console.log(
  `  ${"nutrient".padEnd(14)} ${"per100g x us".padStart(13)} ${"model absolute".padStart(15)} ${"both".padStart(8)}`,
);
for (const nutrient of NUTRIENTS) {
  const cells = (["per100g", "absolute", "both"] as Mode[]).map((mode) => {
    const values = perMode.get(mode)?.get(nutrient) ?? [];
    return `${(100 * median(values)).toFixed(0)}%`;
  });
  console.log(
    `  ${String(nutrient).padEnd(14)} ${cells[0].padStart(13)} ${cells[1].padStart(15)} ${cells[2].padStart(8)}`,
  );
}

console.log("\nAtwater self-consistency (median |P*4 + C*4 + F*9 - kcal| / kcal):");
for (const mode of ["per100g", "absolute", "both"] as Mode[]) {
  const values = atwaterByMode.get(mode) ?? [];
  console.log(`  ${mode.padEnd(10)} ${(100 * median(values)).toFixed(1)}%`);
}

console.log("\nthe model's own arithmetic, from the `both` run:");
console.log(
  `  median error of inPortion vs per100g x weight: ${(100 * median(arithmetic)).toFixed(2)}%`,
);
console.log(`  figures off by more than 2%: ${worstArithmetic.length}/${arithmetic.length}`);
for (const entry of worstArithmetic.slice(0, 6)) {
  console.log(
    `    ${entry.nutrient} of "${entry.label}": said ${entry.said}, its own numbers imply ${entry.implied}`,
  );
}

let perWins = 0;
let absWins = 0;
let ties = 0;
for (const entry of paired.values()) {
  if (!entry.per100g.length || !entry.absolute.length) continue;
  const a = median(entry.per100g);
  const b = median(entry.absolute);
  if (Math.abs(a - b) < 0.01) ties += 1;
  else if (a < b) perWins += 1;
  else absWins += 1;
}
console.log(
  `\npaired by item and nutrient: per100g better ${perWins}, absolute better ${absWins}, tied ${ties}`,
);
