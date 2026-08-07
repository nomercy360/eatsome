import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadGoldenCases } from "./golden";
import { scoreCase } from "./score-case";

const dir = join(import.meta.dirname, "runs");
const file = readdirSync(dir)
  .filter((f) => f.includes("meal-v14"))
  .sort()
  .at(-1) as string;
const rows = readFileSync(join(dir, file), "utf8")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l));
const cases = new Map(loadGoldenCases().map((c) => [c.id, c]));

const byModel = new Map<string, ReturnType<typeof scoreCase>[]>();
for (const row of rows) {
  const golden = cases.get(row.caseId);
  const id = row.model ?? row.modelId ?? row.id;
  if (!golden || !row.raw) continue;
  if (!byModel.has(id)) byModel.set(id, []);
  byModel.get(id)?.push(scoreCase(golden, row.raw));
}

const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);
console.log(
  "| model | pass | recall | structure | dishes reported/expected | counts | panel errors |",
);
console.log("| --- | --- | --- | --- | --- | --- | --- |");
for (const [model, scores] of byModel) {
  const parsed = scores.filter((s) => s.parsed);
  const dishes = parsed.reduce((a, s) => a + s.dishCount, 0);
  const expected = parsed.reduce((a, s) => a + s.dishExpected, 0);
  const cm = parsed.reduce((a, s) => a + s.countMatch, 0);
  const ct = parsed.reduce((a, s) => a + s.countTotal, 0);
  const panel = parsed.reduce((a, s) => a + s.panelWrong.length, 0);
  console.log(
    `| ${model} | ${scores.filter((s) => s.pass).length}/${scores.length} | ${(mean(parsed.map((s) => s.recall)) * 100).toFixed(0)}% | ${(mean(parsed.map((s) => s.structureMatch)) * 100).toFixed(0)}% | ${dishes}/${expected} | ${cm}/${ct} | ${panel} |`,
  );
}
