import { loadGoldenCases } from "./golden";
import { mapGroup, mapPortion } from "./taxonomy";

/**
 * The app's debt to the dataset.
 *
 * The eval now asks the models for the dataset's vocabulary, so nothing here
 * affects scoring any more. What it lists is the work the app has left: every
 * group and measure the golden set uses that `FoodGroup` still cannot express,
 * which is the migration list for after the first results are in.
 *
 *   pnpm eval:coverage
 */
const cases = loadGoldenCases();

const unmappedGroups = new Map<string, { count: number; why: string; cases: Set<string> }>();
const lossyGroups = new Map<string, { count: number; why: string }>();
const unscorablePortions = new Map<string, number>();
let items = 0;
let hidden = 0;
let protein = 0;

for (const one of cases) {
  for (const item of one.golden) {
    items += 1;
    if (item.hidden) hidden += 1;
    if (typeof item.protein_g === "number") protein += 1;

    const mapping = mapGroup(item.group);
    if (mapping.kind === "unmapped") {
      const entry = unmappedGroups.get(item.group) ?? {
        count: 0,
        why: mapping.why,
        cases: new Set<string>(),
      };
      entry.count += 1;
      entry.cases.add(one.id);
      unmappedGroups.set(item.group, entry);
    } else if (mapping.kind === "lossy") {
      const entry = lossyGroups.get(item.group) ?? { count: 0, why: mapping.why };
      entry.count += 1;
      lossyGroups.set(item.group, entry);
    }

    const portion = mapPortion(item);
    if (!portion.portion) {
      unscorablePortions.set(
        item.measure ?? "none",
        (unscorablePortions.get(item.measure ?? "none") ?? 0) + 1,
      );
    }
  }
}

const affected = new Set([...unmappedGroups.values()].flatMap((one) => [...one.cases]));

console.log(`# Golden coverage\n`);
console.log(`${cases.length} cases, ${items} items.\n`);

console.log(`## Groups with no home in FoodGroup\n`);
if (unmappedGroups.size === 0) {
  console.log("None — the taxonomies agree.\n");
} else {
  for (const [group, entry] of [...unmappedGroups].sort((a, b) => b[1].count - a[1].count)) {
    console.log(`- **${group}** — ${entry.count} items across ${entry.cases.size} cases`);
    console.log(`  ${entry.why}`);
  }
  console.log(
    `\n${affected.size} of ${cases.length} cases contain at least one unscorable item. Those cases will lose recall for a reason no prompt can fix.\n`,
  );
}

console.log(`## Mapped, but lossily\n`);
if (lossyGroups.size === 0) console.log("None.\n");
for (const [group, entry] of lossyGroups) {
  console.log(`- **${group}** — ${entry.count} items. ${entry.why}`);
}

console.log(`\n## Portions the schema cannot express\n`);
for (const [measure, count] of unscorablePortions) {
  console.log(`- \`${measure}\` — ${count} of ${items} items scored on group only`);
}

console.log(`\n## Tracks that need their own runs\n`);
console.log(`- hidden items (need the note slot): ${hidden}`);
console.log(`- items carrying protein_g: ${protein}`);
