import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { loadGoldenCases } from "./golden";
import { scoreCase } from "./score-case";

const dir = join(import.meta.dirname, "runs");
const latest = readdirSync(dir).filter((f) => f.endsWith(".jsonl")).sort().at(-1) as string;
const rows = readFileSync(join(dir, latest), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const cases = new Map(loadGoldenCases().map((c) => [c.id, c]));

for (const row of rows) {
  const golden = cases.get(row.caseId);
  if (!golden || !row.raw) continue;
  const s = scoreCase(golden, row.raw);
  const answer = JSON.parse(row.raw);
  console.log("=".repeat(64));
  console.log(`${row.caseId}  ${s.pass ? "PASS" : "FAIL"}  recall ${(s.recall * 100).toFixed(0)}%  structure ${(s.structureMatch * 100).toFixed(0)}%  dishes ${s.dishCount}/${s.dishExpected}  counts ${s.countMatch}/${s.countTotal}`);
  if (s.failures.length) console.log("  failures:", s.failures.join(" | "));
  if (s.missedGroups.length) console.log("  missed:", s.missedGroups.join(", "));
  if (s.spuriousGroups.length) console.log("  spurious:", s.spuriousGroups.join(", "));
  if (s.panelWrong.length) console.log("  panel:", s.panelWrong.join(" | "));
  if (s.caffeineExpected != null) console.log(`  caffeine: expected ${s.caffeineExpected}mg, derived ${s.caffeineActual}mg`);
  console.log("  golden :", golden.dishes.map((d) => `${d.name}${d.count > 1 ? " x" + d.count : ""}`).join(" | "));
  console.log("  answer :", answer.dishes.map((d: any) => `${d.name}${d.count > 1 ? " x" + d.count : ""}[${d.ingredients.map((i: any) => i.group).join(",")}]`).join(" | "));
}
