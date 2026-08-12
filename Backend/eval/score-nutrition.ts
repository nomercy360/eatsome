import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import {
  ATWATER_TOLERANCE,
  atwaterDelta,
  type MealRecognition,
  mealRecognitionSchema,
} from "../src/contracts";
import { geminiResponseSchema } from "../worker/ai/gemini";
import { MEAL_PROMPT_VERSION, MEAL_RECOGNITION_SYSTEM_PROMPT } from "../worker/ai/prompt.generated";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.6-flash";

/**
 * How wrong the app's nutrition is, against meals whose figures were published.
 *
 *   pnpm eval:nutrition
 *   pnpm eval:nutrition -- --case bibimbap-2026-08-07
 *
 * The whole pipeline in one number per nutrient: the model reads the photograph,
 * names foods, weighs them and prices them, and this compares the total against
 * what the canteen or the package actually printed. Weight and composition
 * together — which is the number a person sees, and the only one worth calling
 * accuracy.
 *
 * It runs the *production* prompt and the *production* Gemini schema rather than
 * copies. An eval that asks a different question than the app is how v16 came to
 * report good weights for a month while the app received none.
 *
 * Two things are reported per case and they answer different questions:
 *
 *   error      against the published figure. Needs ground truth, and is the
 *              measurement this set exists for.
 *   atwater    the model's four macronutrients against its own energy figure.
 *              Needs no ground truth at all, so it runs on every case and would
 *              run on a meal nobody published.
 */

type Published = {
  kcal?: number;
  protein_g?: number;
  carbohydrate_g?: number;
  fat_g?: number;
  salt_g?: number;
};

type Case = {
  id: string;
  photo: string;
  source: string;
  published: Published;
  excludes?: string[];
  items?: Array<{ label: string; grams: number }>;
};

const NUTRIENTS = [
  { key: "kcal", published: "kcal" },
  { key: "protein", published: "protein_g" },
  { key: "carbohydrate", published: "carbohydrate_g" },
  { key: "fat", published: "fat_g" },
  { key: "salt", published: "salt_g" },
] as const;

/** Molar mass ratio of sodium chloride to sodium. Arithmetic on a definition. */
const SALT_PER_SODIUM = 58.44 / 22.99;

function loadCases(): Case[] {
  const directory = join(import.meta.dirname, "golden");
  return readdirSync(directory)
    .filter((name) => name.endsWith(".json"))
    .map((name) => JSON.parse(readFileSync(join(directory, name), "utf8")) as Case)
    .sort((a, b) => a.id.localeCompare(b.id));
}

function loadApiKey(): string {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

async function recognize(
  apiKey: string,
  photo: Buffer,
  mimeType: string,
): Promise<MealRecognition> {
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(MODEL)}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: MEAL_RECOGNITION_SYSTEM_PROMPT }] },
      contents: [
        {
          role: "user",
          parts: [
            { text: "Classify the meal closest to the camera." },
            { inlineData: { mimeType, data: photo.toString("base64") } },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: geminiResponseSchema(),
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
  return mealRecognitionSchema.parse(JSON.parse(raw));
}

const words = (value: string) =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter(Boolean);

/**
 * Whether an exclusion names this food, matched on whole words in order.
 *
 * It was a plain `includes` for about an hour, which is long enough to notice
 * that `"steamed white rice".includes("tea")` is true — excluding the tea on a
 * tray would have silently dropped the rice, the largest row in the case, and
 * scored the resulting undercount as a model failure. A substring match over
 * food names is not loose, it is wrong: "tea" is inside "steamed", "steak" and
 * "oatmeal".
 */
export function excludes(label: string, exclusions: string[]): boolean {
  const target = words(label);
  return exclusions.some((exclusion) => {
    const needle = words(exclusion);
    if (!needle.length) return false;
    return target.some((_, index) =>
      needle.every((word, offset) => target[index + offset] === word),
    );
  });
}

/**
 * What the app would show for this meal, with anything the published figure did
 * not cover left out.
 *
 * A published figure that covers part of a tray is genuinely a partial answer:
 * counting the miso soup against a bibimbap's printed calories would score a
 * correct reading as a 20% overestimate.
 */
function totals(recognition: MealRecognition, exclusions: string[]) {
  let kcal = 0;
  let protein = 0;
  let carbohydrate = 0;
  let fat = 0;
  let sodiumMg = 0;
  let excluded = 0;
  // Only what was counted. Reporting the whole tray here compared the soup and
  // the egg against an annotation of the bowl, and made a correct reading look
  // 30% heavy.
  let grams = 0;

  for (const dish of recognition.dishes) {
    // Dish first, and the whole dish goes. A published figure covers dishes —
    // "the bowl, not the soup" — and the model already groups a tray by dish,
    // so matching there is both more robust and more faithful than hoping an
    // exclusion phrase appears in every ingredient underneath it. Written the
    // other way round first, `seasoned egg` failed to match a dish the model
    // called `soy-marinated egg`, and 145 kcal of it was scored against a
    // figure that excludes it.
    if (excludes(dish.name, exclusions)) {
      excluded += dish.ingredients.length;
      continue;
    }
    for (const item of dish.ingredients) {
      if (excludes(item.label, exclusions)) {
        excluded += 1;
        continue;
      }
      grams += item.grams;
      const scale = item.grams / 100;
      kcal += item.per_100g.kcal * scale;
      protein += item.per_100g.protein * scale;
      carbohydrate += item.per_100g.carbohydrate * scale;
      fat += item.per_100g.fat * scale;
      sodiumMg += item.per_100g.sodium_mg * scale;
    }
  }

  return {
    kcal,
    protein,
    carbohydrate,
    fat,
    salt: (sodiumMg * SALT_PER_SODIUM) / 1000,
    excluded,
    grams,
  };
}

const args = process.argv.slice(2);
const only = args.indexOf("--case") === -1 ? null : args[args.indexOf("--case") + 1];
const cases = loadCases().filter((one) => !only || one.id === only);
if (!cases.length) throw new Error(only ? `No case named ${only}.` : "The golden set is empty.");

const apiKey = loadApiKey();
console.log(`Nutrition eval — ${MODEL}, prompt ${MEAL_PROMPT_VERSION}, ${cases.length} case(s)`);
console.log("Ground truth: what whoever served the meal published.\n");

const errors = new Map<string, number[]>(NUTRIENTS.map((n) => [n.key, []]));
const atwaters: number[] = [];
let ran = 0;

for (const one of cases) {
  const photo = join(import.meta.dirname, "photos", one.photo);
  if (!existsSync(photo)) {
    // A case with no photograph can be read but not run. Said out loud rather
    // than skipped quietly: a shrinking denominator is how an eval comes to
    // report a good average over the two cases that still worked.
    console.log(`[${one.id}] SKIPPED — ${one.photo} is not in eval/photos/`);
    continue;
  }
  const mimeType = one.photo.toLowerCase().endsWith(".png") ? "image/png" : "image/jpeg";
  const recognition = await recognize(apiKey, readFileSync(photo), mimeType);
  const app = totals(recognition, one.excludes ?? []);
  ran += 1;

  console.log(
    `[${one.id}] ${one.source} — ${Math.round(app.grams)} g read, ${app.excluded} row(s) excluded`,
  );
  for (const nutrient of NUTRIENTS) {
    const want = one.published[nutrient.published];
    const got = app[nutrient.key];
    if (want == null) continue;
    const error = (got - want) / want;
    errors.get(nutrient.key)?.push(Math.abs(error));
    const sign = error >= 0 ? "+" : "";
    console.log(
      `    ${nutrient.key.padEnd(13)} ${got.toFixed(1).padStart(7)} vs ${String(want).padStart(6)} published   ${sign}${(100 * error).toFixed(0)}%`,
    );
  }

  const delta = atwaterDelta({
    protein: app.protein,
    fat: app.fat,
    carbohydrate: app.carbohydrate,
    kcal: app.kcal,
    sodium_mg: 0,
  });
  if (delta !== null) {
    atwaters.push(delta);
    const verdict = delta <= ATWATER_TOLERANCE ? "ok" : "INCONSISTENT";
    console.log(`    atwater       ${(100 * delta).toFixed(1)}%  ${verdict}`);
  }

  if (one.items?.length) {
    const annotated = one.items.reduce((sum, item) => sum + item.grams, 0);
    console.log(
      `    weight        ${Math.round(app.grams)} g read vs ${annotated} g annotated  ` +
        `${((100 * (app.grams - annotated)) / annotated).toFixed(0)}%`,
    );
  }
  console.log();
}

if (!ran) {
  console.log("Nothing ran. Add the photographs to eval/photos/ and try again.");
  process.exitCode = 1;
} else {
  console.log(`--- ${ran}/${cases.length} case(s) ran ---`);
  for (const nutrient of NUTRIENTS) {
    const values = errors.get(nutrient.key) ?? [];
    if (!values.length) continue;
    const sorted = [...values].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)];
    console.log(
      `  ${nutrient.key.padEnd(13)} median ${(100 * median).toFixed(0).padStart(3)}% over ${values.length} case(s)`,
    );
  }
  if (atwaters.length) {
    const sorted = [...atwaters].sort((a, b) => a - b);
    console.log(
      `  ${"atwater".padEnd(13)} median ${(100 * sorted[Math.floor(sorted.length / 2)]).toFixed(1)}%`,
    );
  }
}
