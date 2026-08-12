#!/usr/bin/env node
/**
 * Retire meals the v21 migration could not carry.
 *
 *   node scripts/drop-empty-meals.mjs            # list them
 *   node scripts/drop-empty-meals.mjs --apply
 *
 * These are meals logged before v17, when quantity was a portion rather than a
 * weight. v21 prices `grams x per 100 g` and there is no weight to price, so
 * they converted to zero dishes — and an empty meal is worse than no meal: it
 * renders as a real entry worth nothing.
 *
 * Retired by appending `meal_deleted`, not by deleting the row. The log is
 * append-only and every device replays it, so an append converges everywhere
 * while a row delete would leave each phone holding an orphan it still shows.
 */
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { rmSync, writeFileSync } from "node:fs";

const apply = process.argv.includes("--apply");
const cwd = join(import.meta.dirname, "..");

function d1(sql) {
  const out = execFileSync(
    "npx",
    ["wrangler", "d1", "execute", "eatsome", "--remote", "--json", "--command", sql],
    { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  return JSON.parse(out.slice(out.indexOf("[")))[0].results;
}

/** UUIDv7: time-ordered, which is what the log sorts and dedupes on. */
function uuidv7(at) {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const ms = BigInt(at);
  for (let i = 0; i < 6; i += 1) bytes[i] = Number((ms >> BigInt(40 - 8 * i)) & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const rows = d1(
  `SELECT id, account_id, device_id, occurred_at, payload_json FROM events
   WHERE kind IN ('meal_logged','meal_revised') AND payload_json LIKE '%"dishes":[]%'`,
);

const meals = new Map();
for (const row of rows) {
  const data = JSON.parse(row.payload_json).data;
  // One deletion per meal, however many events touched it.
  meals.set(data.id, { ...row, mealId: data.id, eatenAt: data.eatenAt });
}

console.log(`empty meals: ${meals.size} (from ${rows.length} events)`);
for (const meal of [...meals.values()].slice(0, 5)) {
  console.log(`  ${meal.mealId}  eaten ${new Date(meal.eatenAt).toISOString().slice(0, 10)}`);
}
if (meals.size > 5) console.log(`  … and ${meals.size - 5} more`);

if (!apply) {
  console.log("\nDry run. Re-run with --apply to append the deletions.");
  process.exit(0);
}

const now = Date.now();
const statements = [...meals.values()].map((meal, index) => {
  const payload = JSON.stringify({ kind: "meal_deleted", data: { mealID: meal.mealId } });
  const literal = (value) => `'${String(value).replace(/'/g, "''")}'`;
  return (
    `INSERT INTO events (id, account_id, device_id, occurred_at, recorded_at, kind, payload_json, received_at) ` +
    `VALUES (${literal(uuidv7(now + index))}, ${literal(meal.account_id)}, ${literal(meal.device_id)}, ` +
    `${meal.occurred_at}, ${now + index}, 'meal_deleted', ${literal(payload)}, ${literal(new Date(now).toISOString())});`
  );
});

const path = join(cwd, ".drop-empty.sql");
writeFileSync(path, `${statements.join("\n")}\n`, "utf8");
execFileSync("npx", ["wrangler", "d1", "execute", "eatsome", "--remote", "--file", path], {
  cwd,
  stdio: "inherit",
});
rmSync(path, { force: true });

const remaining = d1(
  `SELECT COUNT(*) n FROM events WHERE kind IN ('meal_logged','meal_revised')
   AND payload_json LIKE '%"dishes":[]%'
   AND json_extract(payload_json, '$.data.id') NOT IN (
     SELECT json_extract(payload_json, '$.data.mealID') FROM events WHERE kind = 'meal_deleted')`,
)[0].n;
console.log(`\nappended ${statements.length} deletions; empty meals still live: ${remaining}`);
if (remaining > 0) process.exitCode = 1;
