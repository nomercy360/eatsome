import { readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";
import type { GoldenCase } from "./golden";

/**
 * The text track: meals that arrive as words, graded against tiered ground
 * truth. Same dish/ingredient shape as the photo golden — `scoreCase` grades
 * both — plus what only a described meal can be asked.
 *
 * Ground truth here means something different per tier, and `weight_source`
 * says which (see `golden.ts`): a `stated` figure has one right answer, a
 * `counted` one has a canonical answer with the spread real units have, and a
 * `typical` one is a range where the case is really asking whether the size
 * word moved the number. That ranking is prompt v18's own ranking, which is
 * the point: the dataset grades the promise the prompt makes.
 *
 * Provenance of the cases themselves, honestly: the descriptions are authored
 * — written the way a person types into the chat thread — and the ranges are
 * annotated from reference portions, with two cases derived from real logged
 * meals in the photo golden (their `derived_from` says which). Production
 * typed logs with human corrections should join and eventually outnumber
 * these; an authored description can never surprise the way a real one does.
 */
export type TextCase = GoldenCase & {
  /** What the person typed or dictated. The entire model input. */
  said: string;
  /** The photo case this meal came from, when it is a real logged meal. */
  derived_from?: string;
  /**
   * Groups whose presence means the model furnished the meal — the drink or
   * side a meal "usually" has that the person never mentioned. A described
   * meal has no background to inspect, so any of these in the answer is
   * invention, and it gates: a furnished meal scores food nobody ate.
   */
  forbidden_groups?: string[];
  /**
   * Pairs the words genuinely cannot settle — "french toast" fried in butter
   * or in oil. A good answer picks one and names the other in `alternatives`;
   * an answer that silently commits has hidden a fork the person should have
   * been asked about. Each entry is the set of rival groups; the check is that
   * some answered item holds one of them with another as its alternative.
   */
  expected_forks?: string[][];
};

const evalRoot = import.meta.dirname;

export function loadTextCases(): TextCase[] {
  const dir = join(evalRoot, "golden-text");
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const id = basename(name, ".json");
      const raw = JSON.parse(readFileSync(join(dir, name), "utf8")) as Omit<
        TextCase,
        "id" | "photo"
      >;
      return { ...raw, traps: raw.traps ?? [], dishes: raw.dishes ?? [], id, photo: "" };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
}
