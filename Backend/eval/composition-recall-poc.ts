import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.6-flash";

/**
 * Does the model know composition, or does it need a table?
 *
 *   ./node_modules/.bin/tsx eval/composition-recall-poc.ts
 *
 * "Nothing asks a model for a number except a weight" rests on a claim that a
 * model asked for macros answers with 30–50% error. That claim is not measured
 * anywhere in this repo: `labelled.json` holds two meals, one of which publishes
 * a single figure.
 *
 * It is cheap to measure, because the food table IS ground truth: every row
 * carries a published per-100 g figure and the source row it came from. So ask
 * the model for the same figures and compare.
 *
 * Two conditions, because they answer different questions:
 *
 *   sourceName  the source's own name ("Bread, white, commercially prepared").
 *               Isolates composition recall from identification.
 *   alias       what a model actually writes in `label` ("bread"). Includes the
 *               ambiguity penalty of a short name, which is the real case.
 *
 * This measures recall of a published figure. It does NOT measure end-to-end
 * meal error, which also carries weight estimation and is what a user sees.
 */

const SAMPLE_SIZE = 48;
const BATCH_SIZE = 12;

type Nutrients = {
  protein: number;
  fat: number;
  carbohydrate: number;
  kcal: number;
  sodium: number;
};
type Food = { per100g: Nutrients; source: string; basis: string; name: string };

const SYSTEM_PROMPT = `You report the nutrient composition of a named food per 100 g of edible portion.

- Answer for the food as named, prepared the ordinary way for that name.
- protein, fat and carbohydrate in grams; energy in kilocalories; sodium in milligrams.
- All five per 100 g. Never per serving.
- Answer from what published food composition tables report. Do not hedge and do not round to one significant figure.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: ["foods"],
  required: ["foods"],
  properties: {
    foods: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        propertyOrdering: ["index", "protein", "fat", "carbohydrate", "kcal", "sodium"],
        required: ["index", "protein", "fat", "carbohydrate", "kcal", "sodium"],
        properties: {
          index: { type: "INTEGER" },
          protein: { type: "NUMBER", description: "g per 100 g" },
          fat: { type: "NUMBER", description: "g per 100 g" },
          carbohydrate: { type: "NUMBER", description: "g per 100 g" },
          kcal: { type: "NUMBER", description: "kcal per 100 g" },
          sodium: { type: "NUMBER", description: "mg per 100 g" },
        },
      },
    },
  },
} as const;

function loadTable(): Record<string, Food> {
  const path = join(
    import.meta.dirname,
    "../../Core/Sources/ShamanCore/Resources/shaman-config.json",
  );
  const config = JSON.parse(readFileSync(path, "utf8")) as {
    nutrientsPerGram?: { foods: Record<string, Food> };
  };
  const foods = config.nutrientsPerGram?.foods;
  if (!foods) throw new Error("no nutrientsPerGram in shaman-config.json");
  return foods;
}

function loadApiKey(): string {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

type Reply = { index: number } & Nutrients;

async function ask(apiKey: string, names: string[]): Promise<Reply[]> {
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(MODEL)}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [
        {
          role: "user",
          parts: [
            { text: JSON.stringify({ foods: names.map((name, index) => ({ index, name })) }) },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
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
  return (JSON.parse(raw) as { foods: Reply[] }).foods;
}

function median(values: number[]): number {
  if (!values.length) return Number.NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

const foods = loadTable();
const apiKey = loadApiKey();

// A deterministic spread across kinds rather than the first N keys, which would
// be almost entirely fruit and vegetables.
const byKind = new Map<string, string[]>();
for (const key of Object.keys(foods).sort()) {
  const kind = key.split("|")[0];
  byKind.set(kind, [...(byKind.get(kind) ?? []), key]);
}
const sample: string[] = [];
let round = 0;
while (sample.length < SAMPLE_SIZE) {
  let added = false;
  for (const keys of [...byKind.values()]) {
    if (round < keys.length && sample.length < SAMPLE_SIZE) {
      sample.push(keys[round]);
      added = true;
    }
  }
  if (!added) break;
  round += 1;
}

const NUTRIENTS: Array<keyof Nutrients> = ["kcal", "protein", "fat", "carbohydrate", "sodium"];

console.log(`Composition recall POC — ${MODEL}, ${sample.length} sourced rows`);
console.log("Live billable calls; ground truth is the published figure each row carries.\n");

for (const condition of ["sourceName", "alias"] as const) {
  const errors = new Map<keyof Nutrients, number[]>(NUTRIENTS.map((key) => [key, []]));
  const worst: Array<{ name: string; nutrient: string; got: number; want: number; err: number }> =
    [];

  for (let start = 0; start < sample.length; start += BATCH_SIZE) {
    const slice = sample.slice(start, start + BATCH_SIZE);
    const names = slice.map((key) =>
      condition === "sourceName" ? foods[key].name : key.split("|", 2)[1],
    );
    const replies = await ask(apiKey, names);
    const byIndex = new Map(replies.map((reply) => [reply.index, reply]));
    for (const [offset, key] of slice.entries()) {
      const reply = byIndex.get(offset);
      if (!reply) continue;
      const truth = foods[key].per100g;
      for (const nutrient of NUTRIENTS) {
        const want = truth[nutrient];
        const got = reply[nutrient];
        // A published zero cannot carry a percentage. Sodium in particular is
        // legitimately 1–2 mg in plain plant foods, where any absolute miss is
        // a huge ratio; those rows are excluded rather than allowed to set the
        // median.
        if (!Number.isFinite(want) || !Number.isFinite(got) || want < 1) continue;
        const err = Math.abs(got - want) / want;
        errors.get(nutrient)?.push(err);
        worst.push({ name: names[offset], nutrient, got, want, err });
      }
    }
  }

  console.log(`--- condition: ${condition} ---`);
  for (const nutrient of NUTRIENTS) {
    const values = errors.get(nutrient) ?? [];
    const within10 = values.filter((value) => value <= 0.1).length;
    const within25 = values.filter((value) => value <= 0.25).length;
    console.log(
      `  ${String(nutrient).padEnd(13)} median ${(100 * median(values)).toFixed(0).padStart(3)}%   ` +
        `within 10%: ${String(within10).padStart(2)}/${values.length}   ` +
        `within 25%: ${String(within25).padStart(2)}/${values.length}`,
    );
  }
  console.log("  worst five:");
  for (const entry of worst.sort((a, b) => b.err - a.err).slice(0, 5)) {
    console.log(
      `    ${(100 * entry.err).toFixed(0).padStart(4)}%  ${entry.nutrient} of "${entry.name}": ` +
        `said ${entry.got}, published ${entry.want}`,
    );
  }
  console.log();
}
