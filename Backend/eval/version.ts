/**
 * What a run was produced under, with no imports.
 *
 * These three strings are the identity of a run artefact: they land on every
 * row, they key the scoring fingerprint, and a report that cannot name them
 * cannot be compared with any other report. They live alone in this file so
 * that a test asserting the prompt exists does not have to load `sharp` and the
 * whole provider stack to read one filename — that coupling is how the parity
 * test ended up hard-coding `meal-v6.md` beside a harness that had moved on.
 */

/**
 * The prompt under test. Production by default, because an eval that grades a
 * prompt nobody ships reports on a build that does not exist — which is what
 * this did for as long as it pointed at `meal-v14`, a candidate the app never
 * ran and whose vocabulary the app has no fields for.
 *
 * A candidate is measured by overriding it for the run:
 *
 *   EVAL_PROMPT=meal-v17.md EVAL_PROMPT_ID=meal-v17-2026-09-01 pnpm eval:run
 *
 * Versions are immutable; a fix is a new file.
 */
export const EVAL_PROMPT_FILE = process.env.EVAL_PROMPT ?? "meal-v19.md";
export const EVAL_PROMPT_VERSION = process.env.EVAL_PROMPT_ID ?? "meal-v19-2026-08-10";

/**
 * The visible boundary the models are shown: orientation baked in, longest edge
 * at most 1024px, opaque JPEG at quality 82.
 */
export const MODEL_INPUT_VERSION = "jpeg-1024-q82-v1";
