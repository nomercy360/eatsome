import { readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";

/**
 * The dataset's own schema, kept as it was written rather than reshaped to fit
 * the app. Where the two disagree, `taxonomy.ts` says so out loud — a golden set
 * bent to match the code cannot tell you the code is wrong.
 */
export type GoldenItem = {
  name: string;
  group: string;
  alternatives?: string[];
  measure?: "count" | "size" | "package";
  count?: number;
  size?: "S" | "M" | "L";
  weight_g?: number;
  protein_g?: number;
  flags?: string[];
  /** Not visible in the photo: reachable only through the note or a recipe. */
  hidden?: boolean;
};

export type GoldenCase = {
  id: string;
  photo: string;
  scene?: string;
  meal_status?: string;
  dedup_note?: string;
  traps: string[];
  golden: GoldenItem[];
  /**
   * A line the person typed, sent on EVERY track, permanently part of the input.
   *
   * Never the hidden-item note: that one belongs to `--notes`, is generated from
   * the `hidden` flags, and putting it here would hand a plain run the answer
   * the case exists to withhold. IMG_3152 carried exactly that and was only
   * harmless because nothing read this field. This is for cases whose correct
   * answer is undefined without the line:
   * a dinner-party table is either one share or six dishes depending on whether
   * the person said the rest is theirs, and the prompt's nearest-setting rule
   * makes the second reading reachable only through this line. The golden then
   * encodes what is in the photograph under that line — the whole table, at the
   * sizes it is actually served in — not the portion the person ate.
   */
  user_note?: string;
  /** Held back from prompt iteration; see eval/README.md. */
  holdout?: boolean;
};

const evalRoot = import.meta.dirname;

export function loadGoldenCases(): GoldenCase[] {
  const dir = join(evalRoot, "golden");
  const photos = readdirSync(join(evalRoot, "photos"));
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const id = basename(name, ".json");
      const raw = JSON.parse(readFileSync(join(dir, name), "utf8")) as Omit<
        GoldenCase,
        "id" | "photo"
      >;
      // The dataset stores `photos/IMG_1234.jpeg`; `photoPath` adds the
      // directory itself, so the prefix is stripped rather than doubled.
      const declared = (raw as { photo?: string }).photo?.replace(/^photos\//, "");
      const found = photos.find((file) => file.slice(0, file.lastIndexOf(".")) === id);
      return { ...raw, traps: raw.traps ?? [], id, photo: declared ?? found ?? `${id}.JPG` };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
}
