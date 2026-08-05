import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { reserveRecognition } from "./budget";

/** A D1 stub that actually enforces the conditional UPDATE, so the test proves
 *  the reservation and not the mock. */
function db(startingAt = 0) {
  let used = startingAt;
  return {
    env: {
      DB: {
        prepare: (sql: string) => ({
          bind: (..._args: unknown[]) => ({
            run: async () => {
              if (sql.startsWith("INSERT")) return { meta: { changes: 0 } };
              const ceiling = Number(_args[1]);
              if (sql.includes("used + 1")) {
                if (used < ceiling) {
                  used += 1;
                  return { meta: { changes: 1 } };
                }
                return { meta: { changes: 0 } };
              }
              if (used > 0) used -= 1;
              return { meta: { changes: 1 } };
            },
          }),
        }),
      },
    } as unknown as Env,
    get used() {
      return used;
    },
  };
}

describe("the spending ceiling", () => {
  it("hands out exactly the ceiling, however many callers ask at once", async () => {
    // Not destructured: spreading the object would snapshot the getter and the
    // test would assert against a number frozen before anything happened.
    const ledger = db();
    // The bug this replaces: every concurrent request read 399 and proceeded.
    const answers = await Promise.all(
      Array.from({ length: 20 }, () => reserveRecognition(ledger.env, 5)),
    );
    expect(answers.filter(Boolean)).toHaveLength(5);
    expect(ledger.used).toBe(5);
  });

  it("refuses once the day is full", async () => {
    expect(await reserveRecognition(db(400).env, 400)).toBe(false);
  });

  it("treats a ceiling of zero as no ceiling and never touches the ledger", async () => {
    const ledger = db();
    expect(await reserveRecognition(ledger.env, 0)).toBe(true);
    expect(ledger.used).toBe(0);
  });
});
