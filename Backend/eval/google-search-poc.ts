import { existsSync } from "node:fs";
import { join } from "node:path";

import * as z from "zod";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.6-flash";

/**
 * A deliberately isolated live POC for branded-food lookup. It is not imported
 * by the Worker and is not part of the normal test suite. Run it explicitly:
 *
 *   pnpm poc:google-search
 *   pnpm poc:google-search -- --case subway-jp
 *
 * The script loads Backend/.dev.vars when GEMINI_API_KEY is not already in the
 * environment. It never prints the key.
 */

type MarketHint = {
  countryCode: string;
  source: "user_explicit" | "photo_evidence" | "device_region" | "ip_country";
  confidence: "high" | "medium" | "low";
};

type PocCase = {
  id: string;
  food: string;
  requestedServing: string;
  market: MarketHint;
  officialDomains: string[];
  fallbackUrls: string[];
  expected: {
    sourceCalories?: number;
    scaleFactor?: number;
    finalCalories?: number;
  };
};

const cases: PocCase[] = [
  {
    id: "subway-jp",
    food: "Subway アメリカンクラブハウス (American Clubhouse)",
    requestedServing: "one Footlong / フットロング (30 cm)",
    market: { countryCode: "JP", source: "user_explicit", confidence: "high" },
    officialDomains: ["subway.co.jp"],
    // Stable brand-owned table. Discovery is still tested first; this seed is
    // the production-shaped fallback when Search returns an obsolete SKU URL.
    fallbackUrls: ["https://subway.co.jp/documents/pdf/eiyo.pdf"],
    expected: { sourceCalories: 349, scaleFactor: 2, finalCalories: 698 },
  },
  {
    id: "big-mac-jp",
    food: "McDonald's ビッグマック (Big Mac)",
    requestedServing: "one burger",
    market: { countryCode: "JP", source: "user_explicit", confidence: "high" },
    officialDomains: ["mcdonalds.co.jp"],
    fallbackUrls: ["https://www.mcdonalds.co.jp/quality/allergy_Nutrition/nutrient/"],
    expected: { sourceCalories: 524, scaleFactor: 1, finalCalories: 524 },
  },
  {
    id: "big-mac-us",
    food: "McDonald's Big Mac",
    requestedServing: "one burger",
    market: { countryCode: "US", source: "user_explicit", confidence: "high" },
    officialDomains: ["mcdonalds.com"],
    fallbackUrls: ["https://www.mcdonalds.com/us/en-us/product/big-mac.html"],
    expected: { sourceCalories: 580, scaleFactor: 1, finalCalories: 580 },
  },
];

const discoverySchema = z.strictObject({
  status: z.enum(["found", "not_found"]),
  brand: z.string(),
  product: z.string(),
  market_country: z.string(),
  source_url: z.string().nullable(),
  source_title: z.string().nullable(),
  source_kind: z.enum(["product_page", "nutrition_table", "pdf", "none"]),
  notes: z.array(z.string()),
});

const extractionSchema = z.strictObject({
  status: z.enum(["found", "not_found"]),
  source_market_country: z.string(),
  source_product: z.string(),
  source_serving: z.string(),
  requested_serving: z.string(),
  scale_factor: z.number().positive().nullable(),
  scale_basis: z.enum(["same_serving", "official_relation", "geometric_inference", "unsupported"]),
  calories: z.number().nonnegative().nullable(),
  protein_g: z.number().nonnegative().nullable(),
  fat_g: z.number().nonnegative().nullable(),
  carbohydrate_g: z.number().nonnegative().nullable(),
  salt_g: z.number().nonnegative().nullable(),
  sodium_mg: z.number().nonnegative().nullable(),
  notes: z.array(z.string()),
});

const DISCOVERY_JSON_SCHEMA = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["found", "not_found"] },
    brand: { type: "string" },
    product: { type: "string" },
    market_country: { type: "string" },
    source_url: { type: ["string", "null"] },
    source_title: { type: ["string", "null"] },
    source_kind: {
      type: "string",
      enum: ["product_page", "nutrition_table", "pdf", "none"],
    },
    notes: { type: "array", items: { type: "string" } },
  },
  required: [
    "status",
    "brand",
    "product",
    "market_country",
    "source_url",
    "source_title",
    "source_kind",
    "notes",
  ],
} as const;

const EXTRACTION_JSON_SCHEMA = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["found", "not_found"] },
    source_market_country: { type: "string" },
    source_product: { type: "string" },
    source_serving: { type: "string" },
    requested_serving: { type: "string" },
    scale_factor: { type: ["number", "null"] },
    scale_basis: {
      type: "string",
      enum: ["same_serving", "official_relation", "geometric_inference", "unsupported"],
    },
    calories: { type: ["number", "null"] },
    protein_g: { type: ["number", "null"] },
    fat_g: { type: ["number", "null"] },
    carbohydrate_g: { type: ["number", "null"] },
    salt_g: { type: ["number", "null"] },
    sodium_mg: { type: ["number", "null"] },
    notes: { type: "array", items: { type: "string" } },
  },
  required: [
    "status",
    "source_market_country",
    "source_product",
    "source_serving",
    "requested_serving",
    "scale_factor",
    "scale_basis",
    "calories",
    "protein_g",
    "fat_g",
    "carbohydrate_g",
    "salt_g",
    "sodium_mg",
    "notes",
  ],
} as const;

// Prompt under test. Country is evidence with a named source, not a hidden
// assumption based on the model endpoint or the language of the food name.
const DISCOVERY_PROMPT = `Find the current official nutrition source for a branded food.

Market rules:
- Treat the supplied ISO country as the requested product market.
- The market hint has a source and confidence. Explicit user or photo evidence outranks locale.
- Never substitute another country's product, even when it has the same English name.
- Search in the market's local language when useful.
- Use at most two Google Search queries. This lookup is narrow, not open-ended research.
- Return only a direct page or PDF on one of the supplied official brand domains.
- Prefer a nutrition table or PDF over an article, aggregator, search result, or cached snippet.
- If no valid official-market source is findable, return not_found.`;

// This is intentionally a separate call. Search can nominate a URL; only URL
// Context is allowed to establish the numbers that enter a trusted panel.
const EXTRACTION_PROMPT = `Extract branded-food nutrition from the exact official URL in the input.

Evidence rules:
- You must use URL Context. Do not answer from memory or from a search snippet.
- Use only the row explicitly associated with the requested product and market.
- Return source values exactly as published. Do not multiply them.
- If the requested serving is the published serving, use scale_factor 1 and same_serving.
- If a defensible serving relation is needed, return the relation as scale_factor separately.
- Use geometric_inference when the relation is inferred from size (for example, a 30 cm Footlong
  versus a 15 cm Regular) rather than stated by the nutrition source.
- A partial official panel is valid. Return found when the URL explicitly establishes at least one
  requested nutrition value, and leave unavailable values null. Do not reject an official source
  merely because its public page omits some macros.
- If the row association or serving relation is unsafe, return not_found or unsupported.
- Salt equivalent and sodium are different fields. Do not convert either one.
- Never use an aggregator or another country's product.`;

type InteractionStep = {
  type?: string;
  arguments?: { queries?: string[]; urls?: string[] };
  result?: Array<{ status?: string; url?: string }>;
  content?: Array<{ type?: string; text?: string }>;
};

type InteractionResponse = {
  id?: string;
  steps?: InteractionStep[];
  usage?: {
    total_input_tokens?: number;
    total_output_tokens?: number;
    total_thought_tokens?: number;
    total_tool_use_tokens?: number;
    grounding_tool_count?: Array<{ type?: string; count?: number }>;
  };
  error?: { message?: string };
};

type CallResult<T> = {
  parsed: T;
  latencyMs: number;
  searchQueries: string[];
  groundedSearchCount: number;
  urlFetches: Array<{ url: string; status: string }>;
  usage: NonNullable<InteractionResponse["usage"]>;
};

function loadApiKey(): string {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

async function interaction<T>(input: {
  apiKey: string;
  systemInstruction: string;
  prompt: string;
  tools: Array<{ type: "google_search" | "url_context" }>;
  schema: Record<string, unknown>;
  parse: (value: unknown) => T;
  thinkingLevel?: "minimal" | "low";
}): Promise<CallResult<T>> {
  const startedAt = Date.now();
  const response = await fetch(`${BASE_URL}/interactions`, {
    method: "POST",
    headers: {
      "x-goog-api-key": input.apiKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      system_instruction: input.systemInstruction,
      input: input.prompt,
      tools: input.tools,
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: input.schema,
      },
      generation_config: {
        thinking_level: input.thinkingLevel ?? "low",
        tool_choice: "any",
      },
      store: false,
    }),
  });
  const body = (await response.json()) as InteractionResponse;
  if (!response.ok) {
    throw new Error(`Gemini ${response.status}: ${body.error?.message ?? "no error body"}`);
  }

  const steps = body.steps ?? [];
  const raw = steps
    .filter((step) => step.type === "model_output")
    .flatMap((step) => step.content ?? [])
    .filter((content) => content.type === "text")
    .map((content) => content.text ?? "")
    .join("");
  if (!raw) throw new Error("Gemini returned no model_output text.");

  const searchQueries = steps.flatMap((step) =>
    step.type === "google_search_call" ? (step.arguments?.queries ?? []) : [],
  );
  const urlFetches = steps.flatMap((step) =>
    step.type === "url_context_result"
      ? (step.result ?? []).map((result) => ({
          url: result.url ?? "(missing)",
          status: result.status ?? "unknown",
        }))
      : [],
  );
  const usage = body.usage ?? {};
  const groundedSearchCount = (usage.grounding_tool_count ?? [])
    .filter((entry) => entry.type === "google_search")
    .reduce((sum, entry) => sum + (entry.count ?? 0), 0);

  return {
    parsed: input.parse(JSON.parse(raw) as unknown),
    latencyMs: Date.now() - startedAt,
    searchQueries,
    groundedSearchCount,
    urlFetches,
    usage,
  };
}

function marketPrompt(one: PocCase): string {
  return JSON.stringify({
    food: one.food,
    requested_serving: one.requestedServing,
    market_hint: one.market,
    allowed_official_domains: one.officialDomains,
  });
}

function extractionPrompt(one: PocCase, sourceUrl: string): string {
  return JSON.stringify({
    food: one.food,
    requested_serving: one.requestedServing,
    market_hint: one.market,
    official_source_url: sourceUrl,
  });
}

function isOfficialHost(hostname: string, domains: string[]): boolean {
  const host = hostname.toLowerCase().replace(/^www\./, "");
  return domains.some((domain) => {
    const expected = domain.toLowerCase().replace(/^www\./, "");
    return host === expected || host.endsWith(`.${expected}`);
  });
}

async function validateOfficialUrl(
  source: string,
  domains: string[],
): Promise<{ ok: boolean; url: string; reason?: string }> {
  let parsed: URL;
  try {
    parsed = new URL(source);
  } catch {
    return { ok: false, url: source, reason: "not a URL" };
  }
  if (parsed.protocol !== "https:" || !isOfficialHost(parsed.hostname, domains)) {
    return { ok: false, url: source, reason: `host ${parsed.hostname} is not allowlisted` };
  }

  try {
    const response = await fetch(parsed, { method: "GET", redirect: "follow" });
    const finalUrl = response.url || source;
    await response.body?.cancel();
    const finalHost = new URL(finalUrl).hostname;
    if (!response.ok) return { ok: false, url: finalUrl, reason: `HTTP ${response.status}` };
    if (!isOfficialHost(finalHost, domains)) {
      return { ok: false, url: finalUrl, reason: `redirected to non-official host ${finalHost}` };
    }
    return { ok: true, url: finalUrl };
  } catch (error) {
    return {
      ok: false,
      url: source,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}

function scaled(value: number | null, factor: number): number | null {
  return value == null ? null : Math.round(value * factor * 100) / 100;
}

function atwaterDelta(values: {
  calories: number | null;
  protein_g: number | null;
  fat_g: number | null;
  carbohydrate_g: number | null;
}): number | null {
  if (
    values.calories == null ||
    values.protein_g == null ||
    values.fat_g == null ||
    values.carbohydrate_g == null ||
    values.calories === 0
  ) {
    return null;
  }
  const fromMacros = values.protein_g * 4 + values.carbohydrate_g * 4 + values.fat_g * 9;
  return Math.abs(fromMacros - values.calories) / values.calories;
}

function closeTo(actual: number | null, expected: number | undefined): boolean {
  return expected === undefined || (actual !== null && Math.abs(actual - expected) <= 0.01);
}

async function runCase(apiKey: string, one: PocCase) {
  console.log(`\n[${one.id}] ${one.food} — ${one.market.countryCode}`);
  const discovery = await interaction({
    apiKey,
    systemInstruction: DISCOVERY_PROMPT,
    prompt: marketPrompt(one),
    tools: [{ type: "google_search" }],
    schema: DISCOVERY_JSON_SCHEMA,
    parse: discoverySchema.parse,
    thinkingLevel: "minimal",
  });
  console.log(`  search: ${discovery.groundedSearchCount} queries, ${discovery.latencyMs} ms`);
  for (const query of discovery.searchQueries) console.log(`    q: ${query}`);
  console.log(`    candidate: ${discovery.parsed.source_url ?? "not found"}`);

  const candidates = [discovery.parsed.source_url, ...one.fallbackUrls].filter(
    (value, index, all): value is string => Boolean(value) && all.indexOf(value) === index,
  );
  const rejected: string[] = [];
  let extraction: CallResult<z.infer<typeof extractionSchema>> | null = null;
  let sourceUrl: string | null = null;

  for (const candidate of candidates) {
    const validated = await validateOfficialUrl(candidate, one.officialDomains);
    if (!validated.ok) {
      rejected.push(`${candidate} (${validated.reason})`);
      continue;
    }
    const attempted = await interaction({
      apiKey,
      systemInstruction: EXTRACTION_PROMPT,
      prompt: extractionPrompt(one, validated.url),
      tools: [{ type: "url_context" }],
      schema: EXTRACTION_JSON_SCHEMA,
      parse: extractionSchema.parse,
    });
    const fetched = attempted.urlFetches.some(
      (entry) => entry.status === "success" && entry.url !== "(missing)",
    );
    if (!fetched || attempted.parsed.status !== "found") {
      rejected.push(`${validated.url} (URL Context did not establish a product row)`);
      continue;
    }
    extraction = attempted;
    sourceUrl = validated.url;
    break;
  }

  for (const reason of rejected) console.log(`    rejected: ${reason}`);
  if (!extraction || !sourceUrl) throw new Error("No validated official source produced a row.");

  const row = extraction.parsed;
  const factor = row.scale_factor;
  if (factor == null || row.scale_basis === "unsupported") {
    throw new Error(
      `Official row found, but requested serving cannot be scaled (${row.scale_basis}).`,
    );
  }
  const panel = {
    calories: scaled(row.calories, factor),
    protein: scaled(row.protein_g, factor),
    fat: scaled(row.fat_g, factor),
    carbohydrate: scaled(row.carbohydrate_g, factor),
    salt: scaled(row.salt_g, factor),
    // Shaman's NutritionPanel stores sodium in grams, although US sources
    // normally publish milligrams.
    sodium: scaled(row.sodium_mg == null ? null : row.sodium_mg / 1_000, factor),
    basis: "per_container",
  };
  const delta = atwaterDelta(row);
  const checks = [
    closeTo(row.calories, one.expected.sourceCalories),
    closeTo(factor, one.expected.scaleFactor),
    closeTo(panel.calories, one.expected.finalCalories),
    row.source_market_country.toUpperCase() === one.market.countryCode,
  ];

  console.log(`  source: ${sourceUrl}`);
  console.log(
    `  extract: ${extraction.latencyMs} ms, source serving “${row.source_serving}”, scale ×${factor} (${row.scale_basis})`,
  );
  console.log(
    `  source row: ${JSON.stringify({
      calories: row.calories,
      protein: row.protein_g,
      fat: row.fat_g,
      carbohydrate: row.carbohydrate_g,
      salt: row.salt_g,
      sodiumMg: row.sodium_mg,
    })}`,
  );
  console.log(`  final panel: ${JSON.stringify(panel)}`);
  console.log(`  Atwater delta: ${delta == null ? "n/a" : `${(delta * 100).toFixed(1)}%`}`);
  console.log(`  checks: ${checks.every(Boolean) ? "PASS" : "FAIL"}`);
  if (row.notes.length) console.log(`  notes: ${row.notes.join(" | ")}`);

  return {
    id: one.id,
    passed: checks.every(Boolean),
    market: row.source_market_country.toUpperCase(),
    sourceUrl,
    sourceCalories: row.calories,
    finalCalories: panel.calories,
    searchQueries: discovery.groundedSearchCount,
    latencyMs: discovery.latencyMs + extraction.latencyMs,
  };
}

const args = process.argv.slice(2);
const caseIndex = args.indexOf("--case");
const selected = caseIndex === -1 ? cases : cases.filter((one) => one.id === args[caseIndex + 1]);
if (selected.length === 0) {
  throw new Error(`Unknown --case. Choose one of: ${cases.map((one) => one.id).join(", ")}`);
}

const apiKey = loadApiKey();
console.log(`Google Search nutrition POC — ${MODEL}`);
console.log("Live billable calls; no production code or database writes.\n");

const results = [];
for (const one of selected) {
  try {
    results.push(await runCase(apiKey, one));
  } catch (error) {
    console.error(`  ERROR: ${error instanceof Error ? error.message : String(error)}`);
    results.push({ id: one.id, passed: false });
  }
}

if (results.some((result) => !result.passed)) process.exitCode = 1;
if (results.length > 1) {
  const jp = results.find((result) => result.id === "big-mac-jp");
  const us = results.find((result) => result.id === "big-mac-us");
  if (
    jp?.passed &&
    us?.passed &&
    "finalCalories" in jp &&
    "finalCalories" in us &&
    jp.finalCalories === us.finalCalories
  ) {
    console.error("\nMarket isolation FAIL: JP and US Big Mac resolved to the same calories.");
    process.exitCode = 1;
  }
}

console.log(
  `\n${results.filter((result) => result.passed).length}/${results.length} cases passed.`,
);
