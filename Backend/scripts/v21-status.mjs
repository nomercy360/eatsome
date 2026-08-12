#!/usr/bin/env node
/**
 * Who has moved to v21, and who has not been seen since.
 *
 *   node scripts/v21-status.mjs
 *
 * The one thing this CANNOT tell you is whether a phone is holding meals it
 * never sent — that is by definition invisible from here. What it can tell you
 * is who has checked in since the cutover, because a device that has posted
 * under v21 has already forwarded whatever it was holding, and a device that
 * has not is the one still carrying risk.
 */
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const RELEASED_AT = Number(process.argv[2] ?? Date.parse("2026-08-12T06:00:00Z"));

function d1(sql) {
  const out = execFileSync(
    "npx",
    ["wrangler", "d1", "execute", "eatsome", "--remote", "--json", "--command", sql],
    { cwd: join(import.meta.dirname, ".."), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  return JSON.parse(out.slice(out.indexOf("[")))[0].results;
}

const day = (ms) => (ms ? new Date(ms).toISOString().slice(0, 16).replace("T", " ") : "never");

const partitions = d1(`
  SELECT account_id AS id,
         COUNT(*) AS events,
         SUM(CASE WHEN kind IN ('meal_logged','meal_revised') THEN 1 ELSE 0 END) AS meals,
         SUM(CASE WHEN kind IN ('meal_logged','meal_revised')
                   AND payload_json NOT LIKE '%"schemaVersion":21%' THEN 1 ELSE 0 END) AS stale,
         MAX(CASE WHEN device_id LIKE 'server:%' THEN NULL ELSE recorded_at END) AS lastSeen,
         MAX(CASE WHEN device_id LIKE 'server:%'
                   AND kind = 'meal_deleted' THEN 1 ELSE 0 END) AS retiredHere
  FROM events GROUP BY 1 ORDER BY lastSeen DESC`);

const links = new Map(
  d1(`SELECT partition_id, account_id FROM account_partitions`).map((row) => [
    row.partition_id,
    row.account_id,
  ]),
);

console.log(`v21 status — anything last seen before ${day(RELEASED_AT)} has not checked in\n`);
console.log(`  ${"partition".padEnd(30)} ${"events".padStart(6)} ${"meals".padStart(5)} ${"stale".padStart(5)}  last seen`);

let waiting = 0;
for (const row of partitions) {
  // Only a write the app made counts as checking in. The migration's own
  // deletions are excluded above, or every partition it touched would report
  // itself upgraded on the strength of the server having edited it.
  const upgraded = row.lastSeen != null && row.lastSeen >= RELEASED_AT;
  if (!upgraded) waiting += 1;
  const linked = links.has(row.id) ? ` -> ${links.get(row.id).slice(0, 14)}` : "";
  console.log(
    `  ${(row.id.slice(0, 28) + linked).padEnd(30)} ${String(row.events).padStart(6)} ` +
      `${String(row.meals).padStart(5)} ${String(row.stale).padStart(5)}  ${day(row.lastSeen)}` +
      `${upgraded ? "  ✓ checked in" : "  … waiting"}`,
  );
}

const orphans = partitions.filter((row) => row.id.startsWith("device:") && !links.has(row.id));
// `NOT IN` against a set holding a single NULL is never true, so an
// unextractable mealID silently zeroes the whole count. It read 28 against an
// actual 40 before the guard went in.
const live = d1(`
  WITH m AS (SELECT DISTINCT json_extract(payload_json,'$.data.id') id FROM events
             WHERE kind IN ('meal_logged','meal_revised')),
       d AS (SELECT DISTINCT json_extract(payload_json,'$.data.mealID') id FROM events
             WHERE kind = 'meal_deleted'
               AND json_extract(payload_json,'$.data.mealID') IS NOT NULL)
  SELECT COUNT(*) AS n FROM m WHERE id NOT IN (SELECT id FROM d)`)[0].n;
const prices = d1(`SELECT COUNT(*) AS n FROM food_prices`)[0].n;

console.log(`\n  live meals: ${live}   food prices held for late arrivals: ${prices}`);
console.log(`  partitions not seen since the release: ${waiting}`);
if (orphans.length) {
  console.log(
    `\n  ${orphans.length} device partition(s) linked to no account — their history cannot be\n` +
      `  restored on upgrade, because the restore is an account download:`,
  );
  for (const row of orphans) console.log(`    ${row.id}  ${row.events} events  last ${day(row.lastSeen)}`);
}
