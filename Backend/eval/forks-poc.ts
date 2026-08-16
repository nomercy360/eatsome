import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { mealRecognitionSchema } from "../src/contracts";
import { geminiResponseSchema } from "../worker/ai/gemini";
import { MEAL_RECOGNITION_SYSTEM_PROMPT } from "../worker/ai/prompt";

/**
 * How should the model report a choice it cannot make — size, milk, drink,
 * dressing — so the app can ask one question and move the figures?
 *
 *   ./node_modules/.bin/tsx eval/forks-poc.ts [--runs 2] [--only text|image] [--cond sizes,forks,question]
 *
 * Four shapes of the same production prompt and schema. Written against v27,
 * whose menu-item section asked for `sizes`; v28 shipped the `evidence` shape,
 * so today `sizes` runs whatever is in production and the other three rebuild
 * their section on top of it. Results that decided v28 are in `forks-poc.md`.
 *
 *   sizes     what ships (v27: `sizes` + `alternatives`; v28: `forks` with `chosen_from`)
 *   forks     generic `forks: [{axis, options[{label,grams,per_100g,basis,chosen}]}]`
 *             replacing `sizes`; any axis, branded or not; app writes the question
 *   question  as `forks`, but the model also writes the `question` prose
 *   evidence  as `forks`, plus `chosen_from: stated|seen|assumed` per fork, so a
 *             fork the input already settled can be told from one it did not
 *
 * Scored on: how many forks appear and on what, whether the chosen option
 * agrees with the row it explains, whether every option is priced sanely
 * (Atwater), whether unbranded food stays fork-free, and what it costs.
 */

const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const MODEL = "gemini-3.7-flash";

type Cond = "sizes" | "forks" | "question" | "evidence";
type Case = {
  id: string;
  said?: string;
  photo?: string;
  market: string;
  expect: string; // free text: what a good answer looks like
};

const CASES: Case[] = [
  {
    id: "subway-clubhouse",
    said: "subway american clubhouse footlong",
    market: "JP",
    expect: "size fork 15/30cm; kcal ~698 (30cm)",
  },
  {
    id: "chipotle-burrito",
    said: "chicken burrito from chipotle",
    market: "US",
    expect: "one size; maybe rice/beans forks; ~1000 kcal",
  },
  {
    id: "sbux-latte",
    said: "starbucks latte",
    market: "JP",
    expect: "size fork Short/Tall/Grande/Venti; milk fork",
  },
  {
    id: "sbux-grande-oat",
    said: "grande oat milk latte from starbucks",
    market: "US",
    expect: "already decided; no fork or chosen=Grande/oat",
  },
  {
    id: "cafe-cappuccino",
    said: "cappuccino at a cafe",
    market: "GB",
    expect: "unbranded; milk fork plausible; no size ladder",
  },
  {
    id: "bigmac-meal-text",
    said: "big mac meal",
    market: "US",
    expect: "fries size fork; drink fork (coke/zero); Big Mac one size",
  },
  { id: "yoshinoya", said: "yoshinoya gyudon", market: "JP", expect: "size fork 並/大盛/特盛" },
  { id: "lentil-soup", said: "leftover lentil soup, big bowl", market: "GB", expect: "no forks" },
  {
    id: "caesar",
    said: "caesar salad with chicken at a restaurant",
    market: "US",
    expect: "no forks, or a dressing one at most",
  },
  {
    id: "photo-bibimbap",
    photo: "photos/IMG_3263.jpeg",
    market: "JP",
    expect: "no forks (canteen)",
  },
  {
    id: "photo-mentaiko",
    photo: "photos/IMG_3264.jpeg",
    market: "JP",
    expect: "no forks (canteen)",
  },
  {
    id: "photo-bigmac-meal",
    photo: "photos-poc/bigmac-meal-melbourne.jpg",
    market: "AU",
    expect: "drink fork (contents unknown); fries size",
  },
  {
    id: "photo-sbux-psl",
    photo: "photos-poc/starbucks-psl-grande.jpg",
    market: "US",
    expect: "size visible-ish; milk fork",
  },
  {
    id: "photo-subway-6in",
    photo: "photos-poc/subway-turkey-6in.jpg",
    market: "US",
    expect: "size visible: 6in; sub identity fork",
  },
];

// ---------- schema variants ----------

function forkOptions(composition: unknown, withChosen: boolean) {
  const order = ["label", "grams", "per_100g", "basis", ...(withChosen ? ["chosen"] : [])];
  return {
    // No min/maxItems here: Gemini 400s when both this array and the enclosing
    // `forks` array carry maxItems, and accepts either alone. Bounded in the prompt.
    type: "ARRAY",
    items: {
      type: "OBJECT",
      propertyOrdering: order,
      required: order,
      properties: {
        label: {
          type: "STRING",
          description:
            "The option in the words the person would use: 'Footlong', 'Grande', 'oat milk', 'Coke Zero', 'no dressing'. One option per label.",
        },
        grams: {
          type: "NUMBER",
          description: "Edible weight of the whole row if this option is right.",
        },
        per_100g: composition,
        basis: {
          type: "STRING",
          enum: ["published", "derived"],
          description:
            "`published` when someone printed figures for exactly this option; `derived` when it is arithmetic on another one.",
        },
        ...(withChosen
          ? {
              chosen: {
                type: "BOOLEAN",
                description:
                  "True on exactly one option per fork: the one the row's own grams and per_100g already assume.",
              },
            }
          : {}),
      },
    },
  };
}

function forksSchema(composition: unknown, withQuestion: boolean, withEvidence = false) {
  const order = [
    "axis",
    ...(withQuestion ? ["question"] : []),
    ...(withEvidence ? ["chosen_from"] : []),
    "options",
  ];
  return {
    type: "ARRAY",
    maxItems: 3,
    description:
      "Choices the input leaves open that move this row's figures materially — size, milk, which drink, dressing, sugar. Each is a set of complete priced answers for the SAME food, one of them being what the row already assumes. Empty is the normal case. Never a fork on something the input already settled, never a fork whose options differ by little.",
    items: {
      type: "OBJECT",
      propertyOrdering: order,
      required: order,
      properties: {
        axis: {
          type: "STRING",
          description:
            "One or two lowercase words naming the choice: 'size', 'milk', 'drink', 'dressing', 'sugar'.",
        },
        ...(withQuestion
          ? {
              question: {
                type: "STRING",
                description: "The question to put to the person, one short sentence.",
              },
            }
          : {}),
        ...(withEvidence
          ? {
              chosen_from: {
                type: "STRING",
                enum: ["stated", "seen", "assumed"],
                description:
                  "How the chosen option was decided: `stated` when the person's words name it, `seen` when the photograph shows it (a size printed on the cup, a 6-inch wrapper), `assumed` when nothing in the input decides it and you picked the usual one.",
              },
            }
          : {}),
        options: forkOptions(composition, true),
      },
    },
  };
}

function schemaFor(cond: Cond): Record<string, unknown> {
  const base = geminiResponseSchema() as any;
  if (cond === "sizes") return base;
  const ingredient = base.properties.dishes.items.properties.ingredients.items;
  const composition = ingredient.properties.per_100g;
  delete ingredient.properties.sizes;
  delete ingredient.properties.forks;
  ingredient.properties.forks = forksSchema(composition, cond === "question", cond === "evidence");
  ingredient.propertyOrdering = [
    "label",
    "grams",
    "per_100g",
    "preparation",
    "brand",
    "forks",
    "alternatives",
  ];
  ingredient.required = [...ingredient.propertyOrdering];
  return base;
}

// ---------- prompt variants ----------

// v27 heads the section "Menu items — `brand` and `sizes`:", v28 "Menu items — `brand`:".
const SIZES_SECTION_START = "Menu items — `brand`";
const SIZES_SECTION_END = "Composition — `per_100g`:";

const FORKS_SECTION = `Menu items — \`brand\`:
- \`brand\` is the chain or manufacturer whose named menu item this row IS: "Subway", "McDonald's", "Yoshinoya", "Calbee". It is null for everything cooked, everything served loose, and anything added on top of a menu item. A restaurant plate that is not a named chain's named product has no brand.
- It says how the food is *sold*, because that decides how a person can correct it. A bowl of rice is corrected by weight; a Big Mac is not — nobody eats 217 g of Big Mac, they eat one — so a branded row is corrected by naming a different item, a different option, or a different number of them.
- Treat every branded ingredient independently. When one meal contains several branded dishes, search for each product in its own market and populate \`brand\`, \`forks\`, and neighbouring-menu \`alternatives\` on every applicable ingredient. Never stop after grounding the first branded dish.

Open choices — \`forks\`:
- A fork is a choice the input leaves open that moves this row's figures materially, and that the person can answer in one word: which size, which milk, which drink in the cup, dressing or none, sugar or none. It is for the SAME food; a different food is an \`alternative\`.
- Each option is a complete answer priced in full — its own \`label\` in the words the person would use, its own \`grams\` for the whole row, its own \`per_100g\`. Never a factor to apply to another option: a Footlong, a Grande, an oat latte are each their own figures.
- Exactly one option per fork is \`chosen\`: the one this row's own \`grams\` and \`per_100g\` already assume. The row is a real answer on its own; the fork is what the person will be asked afterwards.
- \`basis\` is \`published\` when someone prints figures for exactly that option and \`derived\` when it is arithmetic on another one — a Subway Footlong is twice a Regular and nobody prints it. A derived option is the one most likely to be wrong; still report it, because an absent option is a question the person cannot answer.
- Empty is the normal case. No fork on anything the input already settled — "grande oat latte" has no size fork and no milk fork. No fork on a plate of home cooking, on a canteen tray, on food that comes one way. No fork whose options differ by less than about a fifth of the row's energy. Report only options actually sold or actually plausible; never invent a ladder.
- On a chain's menu item, \`forks\` carries every size the chain sells it in, priced for that market. At most three forks per row, most consequential first.
`;

const QUESTION_ADDENDUM = `- \`question\` is what the app will show above the options: one short sentence, in the second person, in the language of the person's own words.
`;

const EVIDENCE_ADDENDUM = `- \`chosen_from\` says what decided the chosen option: \`stated\` when the person's words name it ("footlong", "grande", "oat"), \`seen\` when the photograph shows it (a size printed on the cup, a wrapper, a visibly small portion), \`assumed\` when nothing in the input decides it and you took the usual one. Only an \`assumed\` fork will be put to the person, so say honestly which it is; still list the other options either way, because a person can be wrong about what they typed.
`;

function promptFor(cond: Cond): string {
  const src = MEAL_RECOGNITION_SYSTEM_PROMPT;
  if (cond === "sizes") return src;
  const a = src.indexOf(SIZES_SECTION_START);
  const b = src.indexOf(SIZES_SECTION_END);
  if (a < 0 || b < 0) throw new Error("v27 prompt sections not where expected");
  const section =
    cond === "question"
      ? FORKS_SECTION + QUESTION_ADDENDUM
      : cond === "evidence"
        ? FORKS_SECTION + EVIDENCE_ADDENDUM
        : FORKS_SECTION;
  return `${src.slice(0, a)}${section}\n${src.slice(b)}`;
}

// ---------- transport ----------

function loadApiKey(): string {
  const vars = join(import.meta.dirname, "..", ".dev.vars");
  if (!process.env.GEMINI_API_KEY && existsSync(vars)) process.loadEnvFile(vars);
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is absent from the environment and Backend/.dev.vars.");
  return key;
}

function userTurn(c: Case): string {
  const sections = [
    c.photo
      ? "Read the meal closest to the camera."
      : "Read the meal described below. There is no photograph; the person's words are the entire input.",
  ];
  if (c.said) sections.push(`From the person who ate it:\n"""\n${c.said}\n"""`);
  sections.push(
    `Where this was bought, from the phone's network rather than from the person — ` +
      `ISO country ${c.market}. Weak evidence: anything the photograph or their own words ` +
      `show about the country outranks it. Use it to price the right market's version of a ` +
      `branded product, never to override what you can see.`,
  );
  return sections.join("\n\n");
}

async function ask(apiKey: string, cond: Cond, c: Case) {
  const parts: any[] = [{ text: userTurn(c) }];
  if (c.photo) {
    const data = readFileSync(join(import.meta.dirname, c.photo)).toString("base64");
    parts.push({ inlineData: { mimeType: "image/jpeg", data } });
  }
  const started = Date.now();
  const res = await fetch(`${BASE_URL}/models/${MODEL}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: promptFor(cond) }] },
      contents: [{ role: "user", parts }],
      tools: [{ googleSearch: {} }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schemaFor(cond),
        thinkingConfig: { thinkingLevel: "low" },
      },
    }),
  });
  const body: any = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${body.error?.message}`);
  const cand = body.candidates?.[0];
  const text = (cand?.content?.parts ?? [])
    .filter((p: any) => p.thought !== true)
    .map((p: any) => p.text ?? "")
    .join("");
  return {
    json: JSON.parse(text),
    finish: cand?.finishReason,
    tokensIn: body.usageMetadata?.promptTokenCount ?? 0,
    tokensOut: body.usageMetadata?.candidatesTokenCount ?? 0,
    tokensThink: body.usageMetadata?.thoughtsTokenCount ?? 0,
    ms: Date.now() - started,
  };
}

// ---------- scoring ----------

const kcalOf = (grams: number, p: any) => (grams * p.kcal) / 100;
const atwaterOff = (p: any) => {
  const derived = p.protein * 4 + p.carbohydrate * 4 + p.fat * 9 + (p.alcohol ?? 0) * 7;
  return p.kcal > 0 ? Math.abs(derived - p.kcal) / p.kcal : 0;
};

type Row = {
  cond: Cond;
  case: string;
  run: number;
  ms: number;
  tokensOut: number;
  tokensThink: number;
  rows: number;
  kcal: number;
  branded: number;
  forks: string[]; // "label:axis[opt1*,opt2](Δkcal)"
  chosenAgree: string; // "n/m"
  atwaterBad: number; // options failing >15%
  unbrandedForks: number;
  questions: string[];
};

function score(cond: Cond, c: Case, run: number, r: Awaited<ReturnType<typeof ask>>): Row {
  const out: Row = {
    cond,
    case: c.id,
    run,
    ms: r.ms,
    tokensOut: r.tokensOut,
    tokensThink: r.tokensThink,
    rows: 0,
    kcal: 0,
    branded: 0,
    forks: [],
    chosenAgree: "",
    atwaterBad: 0,
    unbrandedForks: 0,
    questions: [],
  };
  let agree = 0,
    total = 0;
  for (const d of r.json.dishes ?? []) {
    for (const ing of d.ingredients ?? []) {
      out.rows++;
      out.kcal += kcalOf(ing.grams, ing.per_100g);
      if (ing.brand) out.branded++;
      // v27's `sizes` read as one size fork with nothing chosen; v28 and every
      // variant here return `forks`.
      const forks: any[] = ing.forks
        ? ing.forks
        : (ing.sizes ?? []).length
          ? [{ axis: "size", options: ing.sizes.map((s: any) => ({ ...s, chosen: undefined })) }]
          : [];
      for (const f of forks) {
        if (!ing.brand) out.unbrandedForks++;
        const ks = f.options.map((o: any) => kcalOf(o.grams, o.per_100g));
        const delta = Math.round(Math.max(...ks) - Math.min(...ks));
        for (const o of f.options) if (atwaterOff(o.per_100g) > 0.15) out.atwaterBad++;
        if (ing.forks) {
          total++;
          const chosen = f.options.filter((o: any) => o.chosen);
          if (chosen.length === 1) {
            const o = chosen[0];
            const rowK = kcalOf(ing.grams, ing.per_100g);
            const optK = kcalOf(o.grams, o.per_100g);
            if (
              Math.abs(rowK - optK) / Math.max(rowK, 1) < 0.1 &&
              Math.abs(o.grams - ing.grams) / Math.max(ing.grams, 1) < 0.1
            )
              agree++;
          }
        }
        if (f.question) out.questions.push(f.question);
        out.forks.push(
          `${ing.label}${ing.brand ? `@${ing.brand}` : ""}:${f.axis}${f.chosen_from ? `<${f.chosen_from}>` : ""}[${f.options
            .map(
              (o: any) =>
                `${o.label}${o.chosen ? "*" : ""}${o.basis === "derived" ? "~" : ""} ${Math.round(kcalOf(o.grams, o.per_100g))}`,
            )
            .join(", ")}](Δ${delta})`,
        );
      }
    }
  }
  out.kcal = Math.round(out.kcal);
  out.chosenAgree = total === 0 && cond === "sizes" ? "-" : `${agree}/${total}`;
  return out;
}

// ---------- main ----------

async function main() {
  const argv = process.argv.slice(2);
  const arg = (name: string) => {
    const i = argv.indexOf(`--${name}`);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const runs = Number(arg("runs") ?? 2);
  const only = arg("only");
  const cases_ = arg("cases")?.split(",");
  const conds = (arg("cond") ?? "sizes,forks,question").split(",") as Cond[];
  const key = loadApiKey();
  const cases = CASES.filter((c) =>
    only === "text" ? !c.photo : only === "image" ? !!c.photo : true,
  ).filter((c) => !cases_ || cases_.includes(c.id));

  const jobs: Array<() => Promise<Row>> = [];
  const raw: any[] = [];
  for (const cond of conds)
    for (const c of cases)
      for (let run = 1; run <= runs; run++)
        jobs.push(async () => {
          for (let attempt = 0; ; attempt++) {
            try {
              const r = await ask(key, cond, c);
              // The production shape must also pass the production contract;
              // an answer Gemini emits and Zod refuses is a 502 on the phone.
              if (cond === "sizes") {
                const parsed = mealRecognitionSchema.safeParse(r.json);
                if (!parsed.success)
                  process.stderr.write(
                    `CONTRACT REJECTED ${c.id}#${run}: ${parsed.error.message.slice(0, 300)}\n`,
                  );
              }
              raw.push({ cond, case: c.id, run, ...r });
              const s = score(cond, c, run, r);
              process.stderr.write(
                `. ${cond}/${c.id}#${run} ${s.ms}ms ${s.kcal}kcal forks=${s.forks.length}\n`,
              );
              return s;
            } catch (e) {
              if (attempt >= 2) throw e;
              process.stderr.write(
                `retry ${cond}/${c.id}#${run}: ${(e as Error).message.slice(0, 120)}\n`,
              );
              await new Promise((r) => setTimeout(r, 2000 * (attempt + 1)));
            }
          }
        });

  const results: Row[] = [];
  const CONC = 4;
  let next = 0;
  await Promise.all(
    Array.from({ length: CONC }, async () => {
      while (next < jobs.length) results.push(await jobs[next++]());
    }),
  );

  const outDir = join(import.meta.dirname, "runs");
  mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  writeFileSync(join(outDir, `forks-poc-${stamp}.json`), JSON.stringify({ results, raw }, null, 2));

  // report
  console.log(`\n# forks-poc  model=${MODEL}  runs=${runs}\n`);
  for (const c of cases) {
    console.log(`## ${c.id}  (${c.market})  expect: ${c.expect}`);
    for (const cond of conds) {
      for (const r of results
        .filter((r) => r.case === c.id && r.cond === cond)
        .sort((a, b) => a.run - b.run)) {
        console.log(
          `  ${cond.padEnd(8)} #${r.run}  ${String(r.kcal).padStart(5)} kcal  rows=${r.rows} branded=${r.branded}  forks=${r.forks.length} agree=${r.chosenAgree} atwaterBad=${r.atwaterBad} unbrandedForks=${r.unbrandedForks}  ${r.ms}ms think=${r.tokensThink} out=${r.tokensOut}`,
        );
        for (const f of r.forks) console.log(`             ${f}`);
        for (const q of r.questions) console.log(`             Q: ${q}`);
      }
    }
    console.log();
  }
  console.log("## totals per condition");
  for (const cond of conds) {
    const rs = results.filter((r) => r.cond === cond);
    const sum = (f: (r: Row) => number) => rs.reduce((a, r) => a + f(r), 0);
    const agree = rs.map((r) => r.chosenAgree.split("/").map(Number));
    const ag = agree.reduce((a, [x]) => a + (x || 0), 0);
    const at = agree.reduce((a, [, y]) => a + (y || 0), 0);
    console.log(
      `  ${cond.padEnd(8)} forks=${sum((r) => r.forks.length)} unbrandedForks=${sum((r) => r.unbrandedForks)} atwaterBad=${sum((r) => r.atwaterBad)} chosenAgree=${ag}/${at}  avg ${Math.round(sum((r) => r.ms) / rs.length)}ms think=${Math.round(sum((r) => r.tokensThink) / rs.length)} out=${Math.round(sum((r) => r.tokensOut) / rs.length)}`,
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
