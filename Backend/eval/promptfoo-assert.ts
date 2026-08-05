import { loadGoldenCases } from "./golden";
import { scoreCase } from "./score-case";

/**
 * The custom assertion promptfoo calls per test.
 *
 * All the interesting metrics here are ours — group recall, dedup violations,
 * behavioural rules — so they live in `score-case.ts` and both runners use the
 * same function. A model-graded assertion would be the wrong tool: the output is
 * a closed enum, so there is an exact answer and nothing to have an opinion
 * about.
 */
const cases = loadGoldenCases();

export default function assertMealRecognition(
  output: string,
  context: { vars?: Record<string, unknown> },
) {
  const caseId = String(context.vars?.caseId ?? "");
  const one = cases.find((entry) => entry.id === caseId);
  if (!one) return { pass: false, score: 0, reason: `no golden case named ${caseId}` };

  // The promptfoo path has no hidden-item track: `note` here is the case's own
  // user line, which is not being told about invisible ingredients.
  const score = scoreCase(one, output, false);
  if (!score.parsed) {
    return { pass: false, score: 0, reason: `did not parse: ${score.parseError}` };
  }

  const parts = [
    `recall ${(score.recall * 100).toFixed(0)}%`,
    `precision ${(score.precision * 100).toFixed(0)}%`,
    `portions ${(score.portionMatch * 100).toFixed(0)}%`,
  ];
  if (score.missedGroups.length > 0) parts.push(`missed: ${score.missedGroups.join(",")}`);
  if (score.duplicateGroups.length > 0) parts.push(`dupes: ${score.duplicateGroups.join(",")}`);
  if (score.countTotal > 0) parts.push(`counts ${score.countMatch}/${score.countTotal}`);
  // Reasons, not a verdict: a case that failed on duplicates and one that failed
  // on recall need different fixes.
  if (score.failures.length > 0) parts.push(`failed: ${score.failures.join("; ")}`);
  if (one.traps.length > 0) parts.push(`traps: ${one.traps.join(",")}`);

  return { pass: score.pass, score: score.recall, reason: parts.join(" · ") };
}
