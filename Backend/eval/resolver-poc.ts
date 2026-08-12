import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.6-flash";
const TOP_N = 8;

/**
 * A deliberately isolated live POC for stage-2 label resolution: mapping the
 * free-text `label` recognition returns onto a row of the food composition
 * table. It is not imported by the Worker and is not part of the test suite.
 *
 *   ./node_modules/.bin/tsx eval/resolver-poc.ts
 *   ./node_modules/.bin/tsx eval/resolver-poc.ts --overhead
 *
 * Stage 1 (recognition) is unchanged and not called here. Candidates are
 * retrieved deterministically and kind-scoped; the model only ever picks one of
 * them or rejects them all, so a similarity score can propose but never decide.
 */

type Case = {
  kind: string;
  label: string;
  /** Accepted answers. `null` means "none of these is the same food". */
  accept: Array<string | null>;
  band: string;
  count?: number;
  note?: string;
};

const BATCH_SIZE = 25;

/**
 * Ground truth is hand-authored in eval/resolver-golden.json and printed on
 * every run so the judgements can be argued with. This sizes the idea; it is
 * not an eval.
 */
function loadCases(): Case[] {
  const path = join(import.meta.dirname, "resolver-golden.json");
  return (JSON.parse(readFileSync(path, "utf8")) as { cases: Case[] }).cases;
}

const SYSTEM_PROMPT = `You map a recognised food label onto one row of a food composition table.

Each item gives the broad food kind, the label as recognised, and the candidate rows the table holds for that kind. Choose the candidate naming the same food, or reject them all.

Rules:
- Choose only from the candidates offered for that item. Never invent a name.
- Same food means same composition. A difference of brand, shop, serving format, cut thickness, or a non-culinary adjective is the same food: "subway bread" is bread.
- A difference that changes composition is a different food. Preparation (fried, breaded, battered), a different animal or species, and a different part with a different fat content are all different foods.
- If the label names two or more distinct foods, choose null. Do not pick one of them.
- If nothing offered is the same food, choose null. A rejection is a useful answer and is always better than an approximate one.
- A more general candidate is acceptable when the label is the same food with an inessential qualifier. A more specific candidate is not: never resolve a general label to a specific row it may not be.
- A part of a food is not the food, and neither is something made from it. A yolk, a white, a skin, a crackling, a rind, a trimming, a crust, a filling, a batter, or a roe are each different from the whole food they came from, because the composition differs. None of them resolves to it.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: ["choices"],
  required: ["choices"],
  properties: {
    choices: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        propertyOrdering: ["index", "choice", "why"],
        required: ["index", "choice", "why"],
        properties: {
          index: { type: "INTEGER", description: "The item index this answers." },
          choice: {
            type: "STRING",
            nullable: true,
            description: "Exactly one of that item's candidates, or null to reject them all.",
          },
          why: { type: "STRING", description: "At most eight words." },
        },
      },
    },
  },
} as const;

type Food = { per100g: Record<string, number>; source: string; basis: string; name: string };

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

/**
 * Deterministic, kind-scoped candidate retrieval. Word overlap carries most of
 * the weight; character trigrams break ties and survive a plural or a compound.
 * This proposes and never decides — see the note at the top of the file.
 */
function candidates(foods: Record<string, Food>, kind: string, label: string): string[] {
  const pool = Object.keys(foods)
    .filter((key) => key.startsWith(`${kind}|`))
    .map((key) => key.slice(kind.length + 1));
  const words = (value: string) => new Set(value.split(" "));
  const trigrams = (value: string) => {
    const padded = `  ${value} `;
    const out = new Set<string>();
    for (let i = 0; i < padded.length - 2; i += 1) out.add(padded.slice(i, i + 3));
    return out;
  };
  const jaccard = (a: Set<string>, b: Set<string>) => {
    let shared = 0;
    for (const value of a) if (b.has(value)) shared += 1;
    return shared / (a.size + b.size - shared);
  };
  const lw = words(label);
  const lt = trigrams(label);
  return pool
    .map((row) => ({
      row,
      score: 0.7 * jaccard(lw, words(row)) + 0.3 * jaccard(lt, trigrams(row)),
    }))
    .sort((a, b) => b.score - a.score || a.row.localeCompare(b.row))
    .slice(0, TOP_N)
    .map((entry) => entry.row);
}

type Usage = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
};
type Answer = { index: number; choice: string | null; why: string };

async function resolveBatch(
  apiKey: string,
  items: Array<{ kind: string; label: string; candidates: string[] }>,
): Promise<{ answers: Answer[]; latencyMs: number; usage: Usage }> {
  const prompt = JSON.stringify({
    items: items.map((item, index) => ({
      index,
      kind: item.kind,
      label: item.label,
      candidates: item.candidates,
    })),
  });
  const startedAt = Date.now();
  const response = await fetch(`${BASE_URL}/models/${encodeURIComponent(MODEL)}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        thinkingConfig: { thinkingLevel: "low" },
      },
    }),
  });
  const body = (await response.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string; thought?: boolean }> } }>;
    usageMetadata?: Usage;
    error?: { message?: string };
  };
  if (!response.ok)
    throw new Error(`Gemini ${response.status}: ${body.error?.message ?? "no body"}`);
  const raw = (body.candidates?.[0]?.content?.parts ?? [])
    .filter((part) => part.thought !== true)
    .map((part) => part.text ?? "")
    .join("");
  if (!raw) throw new Error("Gemini returned no output.");
  return {
    answers: (JSON.parse(raw) as { choices: Answer[] }).choices,
    latencyMs: Date.now() - startedAt,
    usage: body.usageMetadata ?? {},
  };
}

const foods = loadTable();
const apiKey = loadApiKey();
const overheadOnly = process.argv.includes("--overhead");

console.log(`Stage-2 resolver POC — ${MODEL}, top ${TOP_N} candidates, kind-scoped`);
console.log("Live billable calls; no production code or database writes.\n");

if (!overheadOnly) {
  const cases = loadCases();
  const results: Array<{ one: Case; answer?: Answer; offered: string[] }> = [];
  let inTokens = 0;
  let outTokens = 0;
  const latencies: number[] = [];

  for (let start = 0; start < cases.length; start += BATCH_SIZE) {
    const slice = cases.slice(start, start + BATCH_SIZE);
    const items = slice.map((one) => ({
      kind: one.kind,
      label: one.label,
      candidates: candidates(foods, one.kind, one.label),
    }));
    const { answers, latencyMs, usage } = await resolveBatch(apiKey, items);
    const byIndex = new Map(answers.map((answer) => [answer.index, answer]));
    latencies.push(latencyMs);
    inTokens += usage.promptTokenCount ?? 0;
    outTokens += usage.candidatesTokenCount ?? 0;
    for (const [offset, one] of slice.entries()) {
      results.push({ one, answer: byIndex.get(offset), offered: items[offset].candidates });
    }
  }

  console.log(
    `ACCURACY — ${cases.length} cases in ${latencies.length} calls of ${BATCH_SIZE}, ` +
      `${latencies.reduce((sum, value) => sum + value, 0)} ms total, ` +
      `${inTokens} in / ${outTokens} out\n`,
  );

  const tally = new Map<string, { ok: number; total: number }>();
  // A model that answers null to everything must not look good. Positives and
  // negatives are scored apart, and a wrong non-null answer is called out: it
  // is the only failure that puts a wrong number on a plate.
  const matrix = { hit: 0, wrongRow: 0, missedResolvable: 0, refusedRight: 0, falseResolve: 0 };
  const failures: string[] = [];

  for (const { one, answer, offered } of results) {
    const choice = answer?.choice ?? null;
    const invented = choice !== null && !offered.includes(choice);
    const ok = !invented && one.accept.includes(choice);
    const band = tally.get(one.band) ?? { ok: 0, total: 0 };
    tally.set(one.band, { ok: band.ok + (ok ? 1 : 0), total: band.total + 1 });

    const resolvable = one.accept.some((value) => value !== null);
    if (resolvable) {
      if (ok && choice !== null) matrix.hit += 1;
      else if (choice === null) matrix.missedResolvable += 1;
      else matrix.wrongRow += 1;
    } else if (choice === null) matrix.refusedRight += 1;
    else matrix.falseResolve += 1;

    if (!ok) {
      failures.push(
        `  FAIL [${one.band}] ${one.kind}|${one.label}\n` +
          `       got ${choice ?? "null"}${invented ? "  <-- NOT OFFERED" : ""}   ` +
          `want ${one.accept.map((value) => value ?? "null").join(" | ")}\n` +
          `       why "${answer?.why ?? "(no answer)"}"${one.note ? `   note: ${one.note}` : ""}`,
      );
    }
  }

  if (failures.length) console.log(`${failures.join("\n")}\n`);

  console.log("  by band:");
  for (const [band, score] of tally) {
    console.log(
      `    ${band.padEnd(11)} ${String(score.ok).padStart(3)}/${String(score.total).padEnd(3)} ` +
        `${Math.round((100 * score.ok) / score.total)}%`,
    );
  }
  const totals = [...tally.values()].reduce(
    (sum, score) => ({ ok: sum.ok + score.ok, total: sum.total + score.total }),
    { ok: 0, total: 0 },
  );
  console.log(
    `    ${"overall".padEnd(11)} ${String(totals.ok).padStart(3)}/${String(totals.total).padEnd(3)} ` +
      `${Math.round((100 * totals.ok) / totals.total)}%`,
  );

  const resolvable = matrix.hit + matrix.wrongRow + matrix.missedResolvable;
  const rejectable = matrix.refusedRight + matrix.falseResolve;
  console.log("\n  where a row exists to be found:");
  console.log(`    resolved correctly     ${matrix.hit}/${resolvable}`);
  console.log(`    resolved to wrong row  ${matrix.wrongRow}/${resolvable}`);
  console.log(`    refused, but could not ${matrix.missedResolvable}/${resolvable}`);
  console.log("\n  where rejecting is the only correct answer:");
  console.log(`    refused correctly      ${matrix.refusedRight}/${rejectable}`);
  console.log(
    `    resolved anyway        ${matrix.falseResolve}/${rejectable}   <-- wrong food on a plate`,
  );
}

// Overhead as it would actually be paid: one batched call per meal, carrying
// only the ingredients the table could not already answer.
const MEALS: Array<{ name: string; items: Array<{ kind: string; label: string }> }> = [
  {
    name: "American Clubhouse sandwich (6 items, 5 unresolved)",
    items: [
      { kind: "bread_flatbread", label: "subway bread" },
      { kind: "poultry", label: "sliced chicken breast" },
      { kind: "processed_meat", label: "ham and bacon" },
      { kind: "vegetable", label: "mixed sandwich vegetables" },
      { kind: "mayonnaise_dressing", label: "mayonnaise dressing" },
    ],
  },
  {
    name: "footlong American Club (6 items, 5 unresolved)",
    items: [
      { kind: "bread_flatbread", label: "submarine bread" },
      { kind: "poultry", label: "sliced turkey breast" },
      { kind: "processed_meat", label: "sliced ham" },
      { kind: "cheese", label: "american cheese" },
      { kind: "vegetable", label: "assorted sandwich vegetables" },
    ],
  },
  {
    name: "single leftover ingredient",
    items: [{ kind: "nuts_seeds", label: "crushed peanuts" }],
  },
];

console.log("\nOVERHEAD — one batched call per meal, unresolved ingredients only");
for (const meal of MEALS) {
  const items = meal.items.map((item) => ({
    ...item,
    candidates: candidates(foods, item.kind, item.label),
  }));
  const runs = [];
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const { latencyMs, usage } = await resolveBatch(apiKey, items);
    runs.push({ latencyMs, usage });
  }
  const times = runs.map((run) => run.latencyMs).sort((a, b) => a - b);
  const usage = runs[0].usage;
  console.log(
    `  ${meal.name}\n    ${times.join(" / ")} ms (3 runs)  ` +
      `tokens ${usage.promptTokenCount ?? "?"} in, ${usage.candidatesTokenCount ?? "?"} out, ${usage.thoughtsTokenCount ?? 0} thinking`,
  );
}
