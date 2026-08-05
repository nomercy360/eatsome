import { loadGoldenCases } from "./golden";

/**
 * Test cases come from the golden file, so there is one list of meals rather
 * than a YAML copy that quietly falls behind it.
 *
 * Holdout cases are excluded by default. They exist to answer whether a prompt
 * generalises, and that answer is worthless once you have been staring at their
 * failures while editing. Run them deliberately, at the end, with
 * EVAL_INCLUDE_HOLDOUT=1.
 */
export default function tests() {
  const cases = loadGoldenCases();
  const includeHoldout = process.env.EVAL_INCLUDE_HOLDOUT === "1";
  return cases
    .filter((one) => includeHoldout || !one.holdout)
    .map((one) => ({
      description: `${one.id}${one.holdout ? " [holdout]" : ""} — ${one.traps.join(", ")}`,
      // `note` is the case's own user line, not the hidden-item track: a case
      // that has one has no defined answer without it, so promptfoo has to send
      // it too or the two runners are asking different questions.
      vars: { caseId: one.id, photo: one.photo, note: one.user_note ?? "" },
    }));
}
