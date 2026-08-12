#!/usr/bin/env node

/**
 * One-release migration from the retired diet `group` field to food `kind`.
 *
 * Safe default: audit only. Applying requires an explicit backup destination:
 *
 *   pnpm taxonomy:audit
 *   pnpm taxonomy:migrate -- --backup ../backups/eatsome-before-food-kind.sql
 *
 * The model's raw response is evidence and is intentionally never rewritten.
 * Canonical parsed results, synced events, eval projections, and copied table
 * ingredients are migrated. Re-running is idempotent.
 */

import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDirectory = dirname(fileURLToPath(import.meta.url));
const backendDirectory = dirname(scriptsDirectory);
const wrangler = join(backendDirectory, "node_modules/wrangler/bin/wrangler.js");

const displayNames = {
  rice: "rice",
  pasta_noodles: "pasta or noodles",
  bread_flatbread: "bread or flatbread",
  cereal_porridge: "cereal or porridge",
  potato: "potato",
  other_starchy_vegetable: "starchy vegetable",
  vegetable: "vegetable",
  mushroom_seaweed: "mushroom or seaweed",
  fruit: "fruit",
  avocado_olive: "avocado or olives",
  legume: "legume",
  soy_product: "soy product",
  nuts_seeds: "nuts or seeds",
  beef: "beef",
  pork: "pork",
  lamb_game: "lamb or game",
  poultry: "poultry",
  processed_meat: "processed meat",
  organ_meat: "organ meat",
  fish: "fish",
  shellfish: "shellfish",
  egg: "egg",
  milk: "milk",
  yogurt: "yogurt",
  cheese: "cheese",
  cream: "cream",
  plant_milk: "plant milk",
  oil: "oil",
  butter_margarine: "butter or margarine",
  mayonnaise_dressing: "mayonnaise or dressing",
  sauce_condiment: "sauce or condiment",
  soup_broth: "soup or broth",
  sugar_honey_syrup: "sugar, honey, or syrup",
  chocolate_candy: "chocolate or candy",
  cake_cookie: "cake or cookie",
  pastry: "pastry",
  frozen_dessert: "frozen dessert",
  savory_snack: "savory snack",
  nutrition_bar: "nutrition bar",
  water: "water",
  coffee: "coffee",
  tea: "tea",
  juice: "juice",
  smoothie: "smoothie",
  soft_sports_energy_drink: "soft, sports, or energy drink",
  beer: "beer",
  wine: "wine",
  spirit_cocktail: "spirit or cocktail",
  supplement: "supplement",
  meal_replacement: "meal replacement",
  unknown: "unidentified food",
};

const currentKinds = new Set(Object.keys(displayNames));

function has(text, ...words) {
  return words.some((word) => text.includes(word));
}

/** A label-aware split is more faithful than the coarse decoder bridge. */
export function legacyFoodKind(group, label = "") {
  const text = String(label).toLowerCase();
  switch (group) {
    case "olive_oil":
    case "vegetable_oil":
      return "oil";
    case "vegetables":
      if (has(text, "potato", "fries", "chips")) return "potato";
      if (has(text, "mushroom", "seaweed", "nori", "wakame")) return "mushroom_seaweed";
      return "vegetable";
    case "fruit":
      return "fruit";
    case "legumes":
      return has(text, "tofu", "tempeh", "natto", "soy") ? "soy_product" : "legume";
    case "fish":
      return has(
        text,
        "shrimp",
        "prawn",
        "crab",
        "lobster",
        "oyster",
        "clam",
        "mussel",
        "scallop",
        "squid",
        "octopus",
      )
        ? "shellfish"
        : "fish";
    case "nuts":
      return "nuts_seeds";
    case "plant_fats":
    case "healthy_fats":
      return "avocado_olive";
    case "whole_grains":
    case "refined_grains":
    case "whole_grain":
    case "refined_grain":
      if (has(text, "rice", "onigiri", "risotto")) return "rice";
      if (has(text, "pasta", "spaghetti", "noodle", "ramen", "udon", "soba"))
        return "pasta_noodles";
      if (has(text, "oat", "porridge", "cereal", "granola", "muesli")) return "cereal_porridge";
      return "bread_flatbread";
    case "white_meat":
      return has(text, "egg", "omelet", "omelette") ? "egg" : "poultry";
    case "red_meat":
      if (has(text, "pork", "chashu", "ham")) return "pork";
      if (has(text, "lamb", "mutton", "venison", "game")) return "lamb_game";
      return "beef";
    case "processed_meat":
      return "processed_meat";
    case "dairy":
      if (has(text, "yogurt", "yoghurt")) return "yogurt";
      if (has(text, "cheese")) return "cheese";
      if (has(text, "cream")) return "cream";
      return "milk";
    case "egg":
      return "egg";
    case "sweets":
      if (has(text, "honey", "syrup", "sugar", "jam")) return "sugar_honey_syrup";
      if (has(text, "cake", "cookie", "biscuit")) return "cake_cookie";
      if (has(text, "ice cream", "gelato", "sorbet")) return "frozen_dessert";
      return "chocolate_candy";
    case "pastry":
      return "pastry";
    case "sugary_drinks":
      return "soft_sports_energy_drink";
    case "coffee":
      return "coffee";
    case "tea":
      return "tea";
    case "juice":
      return "juice";
    case "plant_milk":
      return "plant_milk";
    case "smoothie":
      return "smoothie";
    case "butter":
    case "butter_margarine_cream":
      if (has(text, "mayonnaise", "mayo", "dressing")) return "mayonnaise_dressing";
      if (has(text, "cream")) return "cream";
      return "butter_margarine";
    case "alcohol":
      if (has(text, "wine", "champagne", "prosecco", "sake")) return "wine";
      if (has(text, "cocktail", "whisky", "whiskey", "vodka", "gin", "rum", "spirit"))
        return "spirit_cocktail";
      return "beer";
    case "cooked_tomato_sauce":
    case "sofrito":
    case "sauce":
      return "sauce_condiment";
    case "potatoes":
      return "potato";
    case "other":
      if (has(text, "sauce", "dip", "ketchup", "condiment", "gravy")) return "sauce_condiment";
      if (has(text, "soup", "broth", "stock")) return "soup_broth";
      if (has(text, "potato", "fries")) return "potato";
      if (has(text, "water")) return "water";
      return "unknown";
    default:
      return currentKinds.has(group) ? group : null;
  }
}

function structuredAlternatives(values) {
  if (!Array.isArray(values)) return values;
  return values.map((alternative) => {
    if (typeof alternative !== "string") return alternative;
    const kind = legacyFoodKind(alternative) ?? "unknown";
    return { label: displayNames[kind] ?? "alternative food", kind };
  });
}

/** Migrate canonical JSON while deliberately leaving JSON strings untouched. */
export function migrateFoodJSON(input) {
  let changes = 0;
  function visit(value) {
    if (Array.isArray(value)) return value.map(visit);
    if (value === null || typeof value !== "object") return value;

    const output = {};
    const legacyGroup = typeof value.group === "string" ? value.group : null;
    const kind = legacyGroup ? legacyFoodKind(legacyGroup, value.label) : null;
    for (const [key, child] of Object.entries(value)) {
      if (key === "group" && kind) {
        changes += 1;
        continue;
      }
      if ((key === "alternatives" || key === "modelAlternatives") && Array.isArray(child)) {
        const migrated = structuredAlternatives(child).map(visit);
        if (JSON.stringify(migrated) !== JSON.stringify(child)) changes += 1;
        output[key] = migrated;
      } else {
        output[key] = visit(child);
      }
    }
    if (kind && typeof value.kind !== "string") output.kind = kind;
    return output;
  }
  return { value: visit(input), changes };
}

function parseArguments(argv) {
  const result = { apply: false, remote: true, database: "eatsome", backup: null };
  for (const argument of argv) {
    if (argument === "--") continue;
    if (argument === "--apply") result.apply = true;
    else if (argument === "--local") result.remote = false;
    else if (argument.startsWith("--database=")) result.database = argument.slice(11);
    else if (argument.startsWith("--backup=")) result.backup = argument.slice(9);
    else if (argument !== "--audit") throw new Error(`Unknown argument: ${argument}`);
  }
  return result;
}

function runWrangler(arguments_) {
  const result = spawnSync(process.execPath, [wrangler, ...arguments_], {
    cwd: backendDirectory,
    encoding: "utf8",
    maxBuffer: 50 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "wrangler failed").trim());
  }
  return result.stdout;
}

function query(options, sql) {
  const location = options.remote ? "--remote" : "--local";
  const output = runWrangler([
    "d1",
    "execute",
    options.database,
    location,
    "--json",
    "--command",
    sql,
  ]);
  const start = Math.min(
    ...[output.indexOf("["), output.indexOf("{")].filter((index) => index >= 0),
  );
  const parsed = JSON.parse(output.slice(start));
  const batches = Array.isArray(parsed) ? parsed : [parsed];
  return batches.flatMap((batch) => batch.results ?? []);
}

const sources = [
  {
    name: "events",
    key: "id",
    select:
      "SELECT id, account_id AS accountId, payload_json AS json FROM events WHERE payload_json LIKE '%\"group\"%'",
    columns: ["json"],
    update: "events",
    databaseColumns: { json: "payload_json" },
  },
  {
    name: "recognitions",
    key: "id",
    select:
      "SELECT id, account_id AS accountId, result_json AS json FROM recognitions WHERE result_json LIKE '%\"group\"%'",
    columns: ["json"],
    update: "recognitions",
    databaseColumns: { json: "result_json" },
  },
  {
    name: "meal_evals",
    key: "eventId",
    select:
      "SELECT event_id AS eventId, account_id AS accountId, initial_items_json AS initialItems, final_items_json AS finalItems FROM meal_evals WHERE initial_items_json LIKE '%\"group\"%' OR final_items_json LIKE '%\"group\"%'",
    columns: ["initialItems", "finalItems"],
    update: "meal_evals",
    databaseColumns: { initialItems: "initial_items_json", finalItems: "final_items_json" },
    databaseKey: "event_id",
  },
  {
    name: "table_posts",
    key: "id",
    select:
      "SELECT id, author_account AS accountId, ingredients_json AS ingredients FROM table_posts WHERE ingredients_json LIKE '%\"group\"%'",
    columns: ["ingredients"],
    update: "table_posts",
    databaseColumns: { ingredients: "ingredients_json" },
  },
];

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function collect(options) {
  const operations = [];
  const counts = {};
  const existing = new Set(
    query(options, "SELECT name FROM sqlite_master WHERE type = 'table'").map((row) => row.name),
  );
  for (const source of sources) {
    if (!existing.has(source.update)) {
      counts[source.name] = 0;
      continue;
    }
    const rows = query(options, source.select);
    counts[source.name] = rows.length;
    for (const row of rows) {
      const assignments = [];
      const guards = [];
      for (const column of source.columns) {
        if (typeof row[column] !== "string") continue;
        const original = row[column];
        const migrated = migrateFoodJSON(JSON.parse(original));
        if (migrated.changes === 0) continue;
        const databaseColumn = source.databaseColumns[column];
        const next = JSON.stringify(migrated.value);
        assignments.push(`${databaseColumn} = ${sqlString(next)}`);
        guards.push(`${databaseColumn} = ${sqlString(original)}`);
      }
      if (assignments.length === 0) continue;
      const databaseKey = source.databaseKey ?? source.key;
      operations.push(
        `UPDATE ${source.update} SET ${assignments.join(", ")} WHERE ${databaseKey} = ${sqlString(row[source.key])} AND ${guards.join(" AND ")};`,
      );
    }
  }
  return { operations, counts };
}

function accountSummary(options) {
  return query(
    options,
    `SELECT account_id AS accountId, COUNT(*) AS totalEvents,
       SUM(CASE WHEN kind IN ('meal_logged', 'meal_revised') THEN 1 ELSE 0 END) AS mealEvents,
       SUM(CASE WHEN payload_json LIKE '%"group"%' THEN 1 ELSE 0 END) AS legacyEvents
     FROM events GROUP BY account_id ORDER BY totalEvents DESC`,
  );
}

function resyncSummary(options) {
  return query(
    options,
    `SELECT a.id AS accountId, COUNT(DISTINCT p.partition_id) AS adoptedDevices,
       (SELECT COUNT(*) FROM events e
         WHERE e.account_id = a.id OR e.account_id IN
           (SELECT partition_id FROM account_partitions ap WHERE ap.account_id = a.id)) AS syncEvents,
       (SELECT COUNT(*) FROM events e
         WHERE (e.account_id = a.id OR e.account_id IN
           (SELECT partition_id FROM account_partitions ap WHERE ap.account_id = a.id))
           AND e.kind IN ('meal_logged', 'meal_revised')) AS syncMealEvents
     FROM accounts a LEFT JOIN account_partitions p ON p.account_id = a.id
     GROUP BY a.id ORDER BY syncEvents DESC`,
  );
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const summary = accountSummary(options);
  const resync = resyncSummary(options);
  const migration = collect(options);
  console.log(
    JSON.stringify(
      {
        location: options.remote ? "remote" : "local",
        accounts: summary,
        resyncAccounts: resync,
        legacyRows: migration.counts,
      },
      null,
      2,
    ),
  );

  if (!options.apply) {
    console.log(`Dry run: ${migration.operations.length} rows would be updated. No data changed.`);
    return;
  }
  if (!options.backup) throw new Error("--apply requires --backup=<new-file.sql>");
  if (existsSync(options.backup)) throw new Error(`Backup already exists: ${options.backup}`);

  const location = options.remote ? "--remote" : "--local";
  runWrangler(["d1", "export", options.database, location, "--output", options.backup]);
  if (migration.operations.length === 0) {
    console.log(`Backup written to ${options.backup}; nothing required migration.`);
    return;
  }

  const temporary = mkdtempSync(join(tmpdir(), "eatsome-food-taxonomy-"));
  const sqlFile = join(temporary, "migration.sql");
  try {
    writeFileSync(sqlFile, `${migration.operations.join("\n")}\n`);
    runWrangler(["d1", "execute", options.database, location, "--file", sqlFile]);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }

  const remaining = collect(options);
  if (remaining.operations.length !== 0) {
    throw new Error(
      `${remaining.operations.length} rows still need migration; keep the decoder bridge.`,
    );
  }
  console.log(`Migrated ${migration.operations.length} rows. Backup: ${options.backup}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
