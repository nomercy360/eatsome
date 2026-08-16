#!/usr/bin/env -S pnpm tsx
/**
 * Turn a production D1 export from the v21 database into a data-only restore
 * for the rewrite's squashed v1 schema.
 *
 * This never connects to D1 and never mutates the source dump. It builds the
 * new schema in an in-memory SQLite database, inserts every converted row, and
 * emits SQL only after all constraints and current meal contracts pass.
 *
 *   pnpm tsx scripts/prepare-rewrite-restore.mts \
 *     --source=.wrangler/backups/eatsome-production-pre-reset-2026-08-16.sql \
 *     --output=.wrangler/backups/eatsome-rewrite-restore.sql \
 *     --pricing-cache=.wrangler/backups/eatsome-rewrite-pricing.json \
 *     --price
 *
 * Omit --price for a network-free audit. If the cache is incomplete the audit
 * stops before writing a restore, rather than inventing zeroes for nutrients
 * the old schema never asked for.
 */
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import {
  type Composition,
  compositionSchema,
  loggedEventSchema,
  mealDeleteDataSchema,
  mealEventDataSchema,
} from "../src/contracts.ts";

type Row = Record<string, unknown>;
type PricingCache = {
  model: string;
  generatedAt: string;
  foods: Record<string, Composition>;
};

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const backendDirectory = resolve(scriptDirectory, "..");
const args = new Map(
  process.argv.slice(2).map((argument) => {
    const separator = argument.indexOf("=");
    return separator === -1
      ? [argument, "true"]
      : [argument.slice(0, separator), argument.slice(separator + 1)];
  }),
);

const sourcePath = args.get("--source");
const outputPath = args.get("--output");
const pricingPath = args.get("--pricing-cache");
const shouldPrice = args.has("--price");
const MODEL = "gemini-3.7-flash";
const BATCH_SIZE = 20;

if (!sourcePath || !outputPath || !pricingPath) {
  throw new Error("Required: --source=… --output=… --pricing-cache=… [--price]");
}
if (!existsSync(sourcePath)) throw new Error(`Source dump does not exist: ${sourcePath}`);
if (existsSync(outputPath)) throw new Error(`Refusing to overwrite restore: ${outputPath}`);

function rows(database: DatabaseSync, sql: string): Row[] {
  return database.prepare(sql).all() as Row[];
}

function sqlLiteral(value: unknown): string {
  if (value == null) return "NULL";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`Cannot write non-finite number: ${value}`);
    return String(value);
  }
  if (typeof value === "bigint") return String(value);
  return `'${String(value).replaceAll("'", "''")}'`;
}

function stableUUID(seed: string): string {
  const bytes = createHash("sha256").update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function parseJson(value: unknown, context: string): Record<string, unknown> {
  if (typeof value !== "string") throw new Error(`${context} is not JSON text.`);
  const parsed = JSON.parse(value);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${context} is not a JSON object.`);
  }
  return parsed as Record<string, unknown>;
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function normalizedLabel(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLocaleLowerCase("en-US");
}

const source = new DatabaseSync(":memory:");
source.exec(readFileSync(sourcePath, "utf8"));

const destination = new DatabaseSync(":memory:");
const migration = readFileSync(
  join(backendDirectory, "migrations/0000_init.sql"),
  "utf8",
).replaceAll("--> statement-breakpoint", "");
destination.exec("PRAGMA foreign_keys = ON;");
destination.exec(migration);

const owner = new Map<string, string>();
for (const row of rows(source, "SELECT id FROM accounts"))
  owner.set(String(row.id), String(row.id));
for (const row of rows(source, "SELECT partition_id, account_id FROM account_partitions")) {
  owner.set(String(row.partition_id), String(row.account_id));
}

const mappedEvents = rows(source, "SELECT * FROM events ORDER BY recorded_at, id")
  .map((row) => ({ ...row, mappedAccount: owner.get(String(row.account_id)) }))
  .filter((row) => row.mappedAccount);
const unmappedEvents = Number(
  source
    .prepare(`
  SELECT COUNT(*) AS count FROM events
  WHERE account_id NOT IN (SELECT id FROM accounts)
    AND account_id NOT IN (SELECT partition_id FROM account_partitions)
`)
    .get()?.count ?? 0,
);

const deletedMeals = new Set<string>();
for (const row of mappedEvents) {
  if (row.kind !== "meal_deleted") continue;
  const payload = parseJson(row.payload_json, `event ${row.id}`);
  const deleted = mealDeleteDataSchema.parse(asObject(payload.data));
  deletedMeals.add(`${row.mappedAccount}:${deleted.mealID}`);
}

const sourceMeals = new Map<string, Record<string, unknown>>();
const pricingQueries = new Map<string, string>();
let contentPurgedForDeletedMeals = 0;
for (const row of mappedEvents) {
  if (row.kind !== "meal_logged" && row.kind !== "meal_revised") continue;
  const payload = parseJson(row.payload_json, `event ${row.id}`);
  const meal = asObject(payload.data);
  if (deletedMeals.has(`${row.mappedAccount}:${meal.id}`)) {
    contentPurgedForDeletedMeals += 1;
    continue;
  }
  sourceMeals.set(String(row.id), meal);
  for (const dishValue of asArray(meal.dishes)) {
    for (const itemValue of asArray(asObject(dishValue).items)) {
      const item = asObject(itemValue);
      const itemKey = normalizedLabel(item.label);
      if (!itemKey) throw new Error(`Meal event ${row.id} contains an item with no label.`);
      pricingQueries.set(itemKey, String(item.label).trim());
      for (const alternativeValue of asArray(item.alternatives)) {
        const alternative = asObject(alternativeValue);
        const key = normalizedLabel(alternative.label);
        if (key) pricingQueries.set(key, String(alternative.label).trim());
      }
      for (const sizeValue of asArray(item.sizes)) {
        const size = asObject(sizeValue);
        const key = `${itemKey} :: size :: ${normalizedLabel(size.label)}`;
        pricingQueries.set(key, `${String(item.label).trim()}, size ${String(size.label).trim()}`);
      }
    }
  }
}

let pricing: PricingCache = { model: MODEL, generatedAt: new Date(0).toISOString(), foods: {} };
if (existsSync(pricingPath))
  pricing = JSON.parse(readFileSync(pricingPath, "utf8")) as PricingCache;

function loadApiKey(): string {
  if (!process.env.GEMINI_API_KEY) {
    const vars = join(backendDirectory, ".dev.vars");
    if (existsSync(vars)) process.loadEnvFile(vars);
  }
  if (!process.env.GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  }
  return process.env.GEMINI_API_KEY;
}

const pricingSchema = {
  type: "OBJECT",
  propertyOrdering: ["foods"],
  required: ["foods"],
  properties: {
    foods: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        propertyOrdering: [
          "index",
          "protein",
          "fat",
          "carbohydrate",
          "kcal",
          "sodium_mg",
          "alcohol",
          "caffeine_mg",
        ],
        required: [
          "index",
          "protein",
          "fat",
          "carbohydrate",
          "kcal",
          "sodium_mg",
          "alcohol",
          "caffeine_mg",
        ],
        properties: {
          index: { type: "INTEGER" },
          protein: { type: "NUMBER" },
          fat: { type: "NUMBER" },
          carbohydrate: { type: "NUMBER" },
          kcal: { type: "NUMBER" },
          sodium_mg: { type: "NUMBER" },
          alcohol: { type: "NUMBER" },
          caffeine_mg: { type: "NUMBER" },
        },
      },
    },
  },
};

async function priceBatch(apiKey: string, labels: string[]): Promise<Composition[]> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: {
          parts: [
            {
              text: "Report nutrient composition per 100 g of each named food as eaten. Include seasoning. Alcohol is grams of ethanol and caffeine_mg is milligrams. Keep protein*4 + carbohydrate*4 + fat*9 + alcohol*7 within about 10% of kcal.",
            },
          ],
        },
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
          responseSchema: pricingSchema,
          thinkingConfig: { thinkingLevel: "low" },
        },
      }),
    },
  );
  const body = (await response.json()) as Record<string, unknown>;
  if (!response.ok) {
    throw new Error(`Gemini ${response.status}: ${JSON.stringify(body).slice(0, 500)}`);
  }
  const candidates = asArray(body.candidates);
  const content = asObject(asObject(candidates[0]).content);
  const raw = asArray(content.parts)
    .filter((part) => asObject(part).thought !== true)
    .map((part) => String(asObject(part).text ?? ""))
    .join("");
  const answers = asArray(parseJson(raw, "Gemini pricing response").foods);
  const byIndex = new Map<number, Composition>();
  for (const answerValue of answers) {
    const answer = asObject(answerValue);
    const index = Number(answer.index);
    const { index: _index, ...composition } = answer;
    byIndex.set(index, compositionSchema.parse(composition));
  }
  return labels.map((_, index) => {
    const answer = byIndex.get(index);
    if (!answer) throw new Error(`Gemini omitted pricing answer ${index}.`);
    return answer;
  });
}

let missingPricing = [...pricingQueries.keys()].filter((key) => !pricing.foods[key]);
console.log(`authenticated accounts:       ${rows(source, "SELECT id FROM accounts").length}`);
console.log(`mapped meal events to convert: ${sourceMeals.size}`);
console.log(`distinct foods/sizes to price: ${pricingQueries.size}`);
console.log(`pricing entries missing:        ${missingPricing.length}`);

if (missingPricing.length && shouldPrice) {
  const apiKey = loadApiKey();
  for (let start = 0; start < missingPricing.length; start += BATCH_SIZE) {
    const keys = missingPricing.slice(start, start + BATCH_SIZE);
    const answers = await priceBatch(
      apiKey,
      keys.map((key) => pricingQueries.get(key) as string),
    );
    for (const [index, key] of keys.entries()) pricing.foods[key] = answers[index] as Composition;
    console.log(
      `priced ${Math.min(start + BATCH_SIZE, missingPricing.length)}/${missingPricing.length}`,
    );
  }
  pricing.model = MODEL;
  pricing.generatedAt = new Date().toISOString();
  writeFileSync(pricingPath, `${JSON.stringify(pricing, null, 2)}\n`, { mode: 0o600 });
}

missingPricing = [...pricingQueries.keys()].filter((key) => !pricing.foods[key]);
if (missingPricing.length) {
  console.log("No restore written. Re-run with --price to fill the pricing cache.");
  process.exitCode = 2;
} else {
  // Remote D1 file execution rejects explicit BEGIN/COMMIT statements. Rows
  // are emitted in foreign-key order and Wrangler rolls a failed import back,
  // so the restore needs no transaction wrapper of its own.
  const statements: string[] = [];
  function insert(table: string, columns: string[], values: unknown[]): void {
    const placeholders = columns.map(() => "?").join(", ");
    destination
      .prepare(`INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders})`)
      .run(
        ...values.map((value) => (typeof value === "boolean" ? Number(value) : (value as never))),
      );
    statements.push(
      `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${values.map(sqlLiteral).join(", ")});`,
    );
  }

  for (const row of rows(source, "SELECT id, created_at FROM accounts ORDER BY id")) {
    insert("accounts", ["id", "created_at"], [row.id, row.created_at]);
  }
  for (const row of rows(source, "SELECT * FROM identities ORDER BY provider, subject")) {
    insert(
      "identities",
      ["provider", "subject", "account_id", "email", "email_verified", "created_at"],
      [row.provider, row.subject, row.account_id, row.email, row.email_verified, row.created_at],
    );
  }
  for (const row of rows(source, "SELECT * FROM sessions ORDER BY token_hash")) {
    insert(
      "sessions",
      ["token_hash", "account_id", "device_id", "created_at", "expires_at"],
      [row.token_hash, row.account_id, row.device_id, row.created_at, row.expires_at],
    );
  }

  let fullyRepricedCompositions = 0;
  let alternativeWeightsBackfilled = 0;
  function migrateComposition(oldValue: unknown, priceKey: string): Composition {
    const old = asObject(oldValue);
    const replacement = pricing.foods[priceKey];
    if (!replacement) throw new Error(`Missing price for ${priceKey}`);
    const oldFive = {
      protein: Number(old.protein),
      fat: Number(old.fat),
      carbohydrate: Number(old.carbohydrate),
      kcal: Number(old.kcal),
      sodium_mg: Number(old.sodium_mg),
    };
    const validOldFive =
      oldFive.protein >= 0 &&
      oldFive.protein <= 100 &&
      oldFive.fat >= 0 &&
      oldFive.fat <= 100 &&
      oldFive.carbohydrate >= 0 &&
      oldFive.carbohydrate <= 100 &&
      oldFive.kcal >= 0 &&
      oldFive.kcal <= 900 &&
      oldFive.sodium_mg >= 0 &&
      oldFive.sodium_mg <= 40_000;
    if (!validOldFive) {
      fullyRepricedCompositions += 1;
      return replacement;
    }
    return compositionSchema.parse({
      ...oldFive,
      alcohol: replacement.alcohol,
      caffeine_mg: replacement.caffeine_mg,
    });
  }

  function migrateProvenance(value: unknown): Record<string, string> {
    const old = asObject(value);
    const source = (key: string) => {
      const candidate = String(old[key] ?? "model");
      return candidate === "panel" || candidate === "user" ? candidate : "model";
    };
    return {
      protein: source("protein"),
      fat: source("fat"),
      carbohydrate: source("carbohydrate"),
      kcal: source("kcal"),
      sodium: source("sodium"),
      alcohol: "model",
      caffeine: "model",
    };
  }

  function migratePanel(value: unknown): Record<string, unknown> | null {
    if (!value || typeof value !== "object") return null;
    const old = asObject(value);
    const renamed: Record<string, unknown> = {};
    const keys: [string, string][] = [
      ["calories", "kcal"],
      ["protein", "protein"],
      ["fat", "fat"],
      ["carbohydrate", "carbohydrate"],
      ["salt", "salt"],
      ["sodium", "sodium"],
      ["caffeine", "caffeine"],
    ];
    for (const [before, after] of keys) if (old[before] != null) renamed[after] = old[before];
    return Object.keys(renamed).length ? renamed : null;
  }

  function migrateMeal(old: Record<string, unknown>, eventId: string): Record<string, unknown> {
    const dishes = asArray(old.dishes).map((dishValue, dishIndex) => {
      const dish = asObject(dishValue);
      const items = asArray(dish.items).map((itemValue, itemIndex) => {
        const item = asObject(itemValue);
        const itemKey = normalizedLabel(item.label);
        const itemId = String(item.id);
        const alternatives = asArray(item.alternatives).map(
          (alternativeValue, alternativeIndex) => {
            const alternative = asObject(alternativeValue);
            const key = normalizedLabel(alternative.label);
            if (alternative.grams == null) alternativeWeightsBackfilled += 1;
            return {
              id: stableUUID(`${itemId}:alternative:${alternativeIndex}:${key}`),
              label: alternative.label,
              // Old alternatives could omit weight, in which case choosing one
              // deliberately kept the parent food's weight. The new shape makes
              // that same choice explicit rather than inventing a new amount.
              grams: alternative.grams ?? item.grams,
              per_100g: migrateComposition(alternative.per_100g, key),
            };
          },
        );
        const sizes = asArray(item.sizes).map((sizeValue, sizeIndex) => {
          const size = asObject(sizeValue);
          const key = `${itemKey} :: size :: ${normalizedLabel(size.label)}`;
          return {
            id: stableUUID(`${itemId}:size:${sizeIndex}:${key}`),
            label: size.label,
            grams: size.grams,
            per_100g: migrateComposition(size.per_100g, key),
          };
        });
        const migrated: Record<string, unknown> = {
          id: item.id,
          label: item.label,
          grams: item.grams,
          per_100g: migrateComposition(item.per_100g, itemKey),
          provenance: migrateProvenance(item.provenance),
          preparation: asArray(item.preparation),
          alternatives,
          sizes,
        };
        if (item.brand != null) migrated.brand = item.brand;
        if (!migrated.id)
          migrated.id = stableUUID(`${eventId}:dish:${dishIndex}:item:${itemIndex}`);
        return migrated;
      });
      const migrated: Record<string, unknown> = {
        id: dish.id,
        count: dish.count,
        items,
      };
      if (dish.name != null) migrated.name = dish.name;
      const panel = migratePanel(dish.panel);
      if (panel) migrated.panel = panel;
      return migrated;
    });

    const migrated: Record<string, unknown> = {
      id: old.id,
      schemaVersion: 1,
      eatenAt: old.eatenAt,
      dishes,
      source: old.source === "recipe" ? "manual" : old.source,
      wasCorrected: old.wasCorrected ?? false,
    };
    for (const key of ["photoHash", "note", "share", "messageID"] as const) {
      if (old[key] != null) migrated[key] = old[key];
    }
    return mealEventDataSchema.parse(migrated);
  }

  type Projection = {
    accountId: string;
    mealId: string;
    photoHash: string | null;
    eventId: string;
    recordedAt: number;
  };
  const projection = new Map<string, Projection>();
  let copiedEvents = 0;
  for (const row of mappedEvents) {
    let payload = parseJson(row.payload_json, `event ${row.id}`);
    if (row.kind === "meal_logged" || row.kind === "meal_revised") {
      const oldMeal = sourceMeals.get(String(row.id));
      if (!oldMeal) continue;
      payload = { ...payload, data: migrateMeal(oldMeal, String(row.id)) };
    }
    const event = loggedEventSchema.parse({
      id: row.id,
      occurredAt: row.occurred_at,
      recordedAt: row.recorded_at,
      payload,
    });
    const payloadJson = JSON.stringify(event.payload);
    insert(
      "events",
      [
        "id",
        "account_id",
        "device_id",
        "occurred_at",
        "recorded_at",
        "kind",
        "payload_json",
        "received_at",
      ],
      [
        row.id,
        row.mappedAccount,
        row.device_id,
        row.occurred_at,
        row.recorded_at,
        row.kind,
        payloadJson,
        row.received_at,
      ],
    );
    copiedEvents += 1;

    let mealId: string | undefined;
    let photoHash: string | null = null;
    if (row.kind === "meal_logged" || row.kind === "meal_revised") {
      const meal = mealEventDataSchema.parse(event.payload.data);
      mealId = meal.id;
      photoHash = meal.photoHash?.toLowerCase() ?? null;
    } else if (row.kind === "meal_deleted") {
      mealId = mealDeleteDataSchema.parse(event.payload.data).mealID;
    }
    if (mealId) {
      const candidate: Projection = {
        accountId: String(row.mappedAccount),
        mealId,
        photoHash,
        eventId: String(row.id),
        recordedAt: Number(row.recorded_at),
      };
      const key = `${candidate.accountId}:${candidate.mealId}`;
      const current = projection.get(key);
      if (
        !current ||
        candidate.recordedAt > current.recordedAt ||
        (candidate.recordedAt === current.recordedAt && candidate.eventId > current.eventId)
      ) {
        projection.set(key, candidate);
      }
    }
  }

  let skippedRecognitions = 0;
  for (const row of rows(source, "SELECT * FROM recognitions ORDER BY id")) {
    const mappedAccount = owner.get(String(row.account_id));
    if (!mappedAccount) {
      skippedRecognitions += 1;
      continue;
    }
    insert(
      "recognitions",
      [
        "id",
        "account_id",
        "photo_hash",
        "input_fingerprint",
        "prompt_version",
        "model",
        "result_json",
        "raw_model_json",
        "provider_request_id",
        "input_tokens",
        "output_tokens",
        "latency_ms",
        "created_at",
      ],
      [
        row.id,
        mappedAccount,
        row.photo_hash,
        row.input_fingerprint,
        row.prompt_version,
        row.model,
        row.result_json,
        row.raw_model_json,
        row.provider_request_id,
        row.input_tokens,
        row.output_tokens,
        row.latency_ms,
        row.created_at,
      ],
    );
  }

  for (const row of rows(source, "SELECT * FROM media_objects ORDER BY account_id, photo_hash")) {
    const mappedAccount = owner.get(String(row.account_id));
    if (!mappedAccount) continue;
    insert(
      "media_objects",
      [
        "account_id",
        "photo_hash",
        "object_key",
        "mime_type",
        "byte_size",
        "created_at",
        "stored_at",
      ],
      [
        mappedAccount,
        row.photo_hash,
        row.object_key,
        row.mime_type,
        row.byte_size,
        row.created_at,
        row.stored_at,
      ],
    );
  }
  for (const value of projection.values()) {
    insert(
      "meal_media",
      ["account_id", "meal_id", "photo_hash", "event_id", "recorded_at"],
      [value.accountId, value.mealId, value.photoHash, value.eventId, value.recordedAt],
    );
  }
  for (const row of rows(source, "SELECT day, used FROM budget ORDER BY day")) {
    insert("budget", ["day", "used"], [row.day, row.used]);
  }

  destination.exec("PRAGMA foreign_key_check;");
  writeFileSync(outputPath, `${statements.join("\n")}\n`, { mode: 0o600 });

  console.log(`restore written:              ${outputPath}`);
  console.log(`events copied:                ${copiedEvents}`);
  console.log(`unmapped events archived only:${unmappedEvents}`);
  console.log(`deleted meal bodies purged:   ${contentPurgedForDeletedMeals}`);
  console.log(`recognitions skipped anonymous:${skippedRecognitions}`);
  console.log(`meal-media rows rebuilt:      ${projection.size}`);
  console.log(`compositions fully repriced:  ${fullyRepricedCompositions}`);
  console.log(`alternative weights inherited:${alternativeWeightsBackfilled}`);
}
