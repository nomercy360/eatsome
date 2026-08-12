#!/usr/bin/env node
/**
 * v20 meals -> v21 meals, once.
 *
 *   node scripts/migrate-v21.mjs --audit
 *   node scripts/migrate-v21.mjs --apply --backup=../backups/eatsome-before-v21.sql
 *
 * v21 stores composition on every food instead of deriving it at render time
 * from a table and a taxonomy. That is what makes an event readable forever
 * with no compatibility branches — and it means the figures for meals already
 * in the log have to be written down before the code that could derive them is
 * gone. This is that step, and it is the only thing in the system that rewrites
 * a stored event.
 *
 * It re-prices; it does not re-recognise. The stored rows already carry a label
 * and a weight, which is everything a pricing pass needs, and re-reading the
 * photograph would re-decide identity and weight — discarding the corrections
 * the person made afterwards. There are `meal_revised` events in this database;
 * a delta applied to a base that changed is not the same correction.
 *
 * Raw model responses are never touched. They are the evidence that says what
 * was actually asked and answered, and a migration that edits its own evidence
 * cannot be checked.
 */
import { existsSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.6-flash";
const BATCH = 20;
const SCHEMA_VERSION = 21;

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const backup = args.find((value) => value.startsWith("--backup="))?.slice("--backup=".length);

function d1(sql, { json = true } = {}) {
  const out = execFileSync(
    "npx",
    ["wrangler", "d1", "execute", "eatsome", "--remote", ...(json ? ["--json"] : []), "--command", sql],
    { cwd: join(import.meta.dirname, ".."), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  if (!json) return out;
  return JSON.parse(out.slice(out.indexOf("[")))[0].results;
}

function loadApiKey() {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

const PRICING_PROMPT = `You report nutrient composition for named foods.

For each item return composition PER 100 g of edible portion, prepared the ordinary way for its name: protein, fat and carbohydrate in grams, kcal in kilocalories, sodium_mg in milligrams. Never per serving and never for a stated weight.

Price the food as it is eaten, seasoning included. Keep protein x 4 + carbohydrate x 4 + fat x 9 within about 10% of kcal.`;

const PRICING_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: ["foods"],
  required: ["foods"],
  properties: {
    foods: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        propertyOrdering: ["index", "protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
        required: ["index", "protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
        properties: {
          index: { type: "INTEGER" },
          protein: { type: "NUMBER" },
          fat: { type: "NUMBER" },
          carbohydrate: { type: "NUMBER" },
          kcal: { type: "NUMBER" },
          sodium_mg: { type: "NUMBER" },
        },
      },
    },
  },
};

async function price(apiKey, labels) {
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(MODEL)}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: PRICING_PROMPT }] },
      contents: [
        {
          role: "user",
          parts: [
            { text: JSON.stringify({ foods: labels.map((name, index) => ({ index, name })) }) },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: PRICING_SCHEMA,
        thinkingConfig: { thinkingLevel: "low" },
      },
    }),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${body.error?.message ?? "no body"}`);
  const raw = (body.candidates?.[0]?.content?.parts ?? [])
    .filter((part) => part.thought !== true)
    .map((part) => part.text ?? "")
    .join("");
  return JSON.parse(raw).foods;
}

/**
 * The distinct foods across every meal, so a label eaten nine times is priced
 * once. `(label)` is the whole key: composition is a property of the food, and
 * the weight it was eaten at is already on the row.
 */
function collectLabels(meals) {
  const labels = new Set();
  for (const meal of meals) {
    for (const item of meal.data.items ?? []) {
      const label = (item.label ?? "").trim();
      if (label) labels.add(label.toLowerCase());
    }
  }
  return [...labels].sort();
}

/** A v20 payload, rebuilt in the v21 shape with figures written down. */
function convert(data, priced) {
  const byDish = new Map();
  const order = [];
  for (const item of data.items ?? []) {
    const name = item.dish ?? null;
    if (!byDish.has(name)) {
      byDish.set(name, []);
      order.push(name);
    }
    const label = (item.label ?? "").trim();
    const per100g = priced.get(label.toLowerCase());
    // A row with no label or no price is not guessed at. It is dropped and
    // reported: an invented figure in the one place reserved for stored facts
    // is worse than a meal that is visibly short a row.
    if (!label || !per100g || item.grams == null) continue;
    byDish.get(name).push({
      id: item.id,
      label,
      grams: item.grams,
      per_100g: per100g,
      // Every figure came from the same pricing pass, and the person did not
      // ask for it — so `model`, not `user`, even on a meal they corrected.
      // What they corrected was the food, and the food is what was priced.
      provenance: {
        protein: "model",
        fat: "model",
        carbohydrate: "model",
        kcal: "model",
        sodium: "model",
      },
      preparation: item.preparation ?? [],
      alternatives: [],
    });
  }

  const stored = new Map((data.storedDishes ?? []).map((dish) => [dish.name || null, dish]));
  const dishes = order
    .map((name) => {
      const items = byDish.get(name) ?? [];
      if (!items.length) return null;
      const source = stored.get(name);
      return {
        id: source?.id ?? crypto.randomUUID(),
        name: name || null,
        count: source?.count ?? 1,
        panel: source?.panel ?? null,
        items,
      };
    })
    .filter(Boolean);

  return {
    id: data.id,
    schemaVersion: SCHEMA_VERSION,
    eatenAt: data.eatenAt,
    dishes,
    source: data.source,
    share: data.share ?? null,
    note: data.note ?? null,
    recognitionRating: data.recognitionRating ?? null,
    messageID: data.messageID ?? null,
    photoHash: data.photoHash ?? null,
    // The evidence keeps its raw answer verbatim; only its shape moves.
    recognitionEvidence: data.recognitionEvidence
      ? {
          promptVersion: data.recognitionEvidence.promptVersion,
          model: null,
          rawModelJSON: data.recognitionEvidence.rawModelJSON,
          initialDishes: [],
        }
      : null,
    wasCorrected: data.wasCorrected ?? false,
    recipeID: data.recipeID ?? null,
  };
}

const rows = d1(
  `SELECT id, payload_json AS json FROM events
   WHERE kind IN ('meal_logged','meal_revised')`,
);
const meals = rows
  .map((row) => ({ id: row.id, payload: JSON.parse(row.json) }))
  .map((row) => ({ ...row, data: row.payload.data }))
  .filter((row) => row.data && row.data.schemaVersion !== SCHEMA_VERSION);

const labels = collectLabels(meals);
console.log(`meal events needing v21: ${meals.length}`);
console.log(`distinct foods to price:  ${labels.length}`);
console.log(`rows with no label or no weight will be dropped and listed.`);

if (!apply) {
  console.log("\nDry run. Nothing was priced and nothing was written.");
  console.log("Re-run with --apply --backup=<path> to migrate.");
  process.exit(0);
}

if (!backup) throw new Error("--apply requires --backup=<path>. Export before rewriting the log.");
console.log(`\nexporting to ${backup} …`);
execFileSync("npx", ["wrangler", "d1", "export", "eatsome", "--remote", "--output", backup], {
  cwd: join(import.meta.dirname, ".."),
  stdio: "inherit",
});

const apiKey = loadApiKey();
const priced = new Map();
for (let start = 0; start < labels.length; start += BATCH) {
  const slice = labels.slice(start, start + BATCH);
  const answers = await price(apiKey, slice);
  for (const answer of answers) {
    const label = slice[answer.index];
    if (!label) continue;
    const { index, ...per100g } = answer;
    priced.set(label, per100g);
  }
  console.log(`  priced ${Math.min(start + BATCH, labels.length)}/${labels.length}`);
}

// The price of every label, kept so the legacy ingest endpoint can convert a
// line that arrives after this run without a model call inside a sync request.
// A late line comes off the same trays as the ones priced here, so it almost
// always hits.
d1(
  `CREATE TABLE IF NOT EXISTS food_prices (
     label TEXT PRIMARY KEY, per_100g_json TEXT NOT NULL, priced_at INTEGER NOT NULL);`,
  { json: false },
);
const pricedAt = meals.reduce((latest, meal) => Math.max(latest, meal.data.eatenAt ?? 0), 0);
for (const [label, per100g] of priced) {
  const value = JSON.stringify(JSON.stringify(per100g)).replace(/'/g, "''").replace(/^"|"$/g, "'");
  const key = JSON.stringify(label).replace(/'/g, "''").replace(/^"|"$/g, "'");
  d1(
    `INSERT OR REPLACE INTO food_prices (label, per_100g_json, priced_at) VALUES (${key}, ${value}, ${pricedAt});`,
    { json: false },
  );
}
console.log(`stored ${priced.size} food prices for late arrivals`);

let dropped = 0;
const statements = [];
for (const meal of meals) {
  const before = (meal.data.items ?? []).length;
  const data = convert(meal.data, priced);
  const after = data.dishes.reduce((sum, dish) => sum + dish.items.length, 0);
  if (after < before) {
    dropped += before - after;
    console.log(`  ${meal.data.id}: ${before - after} row(s) dropped`);
  }
  const payload = JSON.stringify({ ...meal.payload, data });
  statements.push(
    `UPDATE events SET payload_json = ${JSON.stringify(payload).replace(/'/g, "''").replace(/^"|"$/g, "'")} WHERE id = '${meal.id}';`,
  );
}

for (const statement of statements) d1(statement, { json: false });

const remaining = d1(
  `SELECT COUNT(*) AS n FROM events
   WHERE kind IN ('meal_logged','meal_revised') AND payload_json NOT LIKE '%"schemaVersion":21%'`,
)[0].n;

console.log(`\nmigrated ${statements.length} meal events, dropped ${dropped} unpriceable rows`);
console.log(`meal events still not v21: ${remaining}`);
if (remaining > 0) process.exitCode = 1;
