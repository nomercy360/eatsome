import { DatabaseSync } from "node:sqlite";
import { describe, expect, it } from "vitest";
import type { IngestEventsRequest } from "../../src/contracts";
import type { Env } from "../env";
import { ingestEvents, pullEvents, purgeDeletedMealContent } from "./events";

type CapturedStatement = { sql: string; values: unknown[] };

function capturingDatabase() {
  const batches: CapturedStatement[][] = [];
  const database = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return { sql, values } as unknown as D1PreparedStatement;
        },
      };
    },
    async batch(statements: D1PreparedStatement[]) {
      batches.push(statements as unknown as CapturedStatement[]);
      return [];
    },
  };
  return { database: database as unknown as D1Database, batches };
}

const mealID = "0198F222-AADB-7E00-8000-ABCDEF012345";

function deletionEvents(): IngestEventsRequest["events"] {
  return [
    {
      id: "0198F333-AADB-7E00-8000-ABCDEF012345",
      occurredAt: 1_700_000_000_000,
      recordedAt: 1_700_000_000_100,
      payload: { kind: "meal_deleted", data: { mealID } },
    },
  ];
}

describe("meal deletion cleanup", () => {
  it("purges the meal's content and leaves its tombstone for the other phones", async () => {
    const fake = capturingDatabase();
    await purgeDeletedMealContent(fake.database, "acct:one", deletionEvents());

    expect(fake.batches).toHaveLength(1);
    expect(fake.batches[0]).toHaveLength(1);
    const statement = fake.batches[0]?.[0];
    expect(statement?.sql).toContain("DELETE FROM events");
    // Only the content. Deleting the `meal_deleted` row too would mean a second
    // device never learns of the deletion and re-uploads the meal it still
    // holds — the deletion would undo itself on the next sync.
    expect(statement?.sql).toContain("kind IN ('meal_logged', 'meal_revised')");
    expect(statement?.sql).not.toContain("meal_deleted");
    expect(statement?.values).toEqual(["acct:one", mealID]);
  });

  it("does not mutate API history when a batch has no deletion", async () => {
    const fake = capturingDatabase();
    const events = deletionEvents();
    const original = events[0];
    if (!original) throw new Error("Expected a deletion fixture.");
    events[0] = {
      ...original,
      payload: { kind: "message_deleted", data: { messageID: mealID } },
    };

    await purgeDeletedMealContent(fake.database, "acct:one", events);
    expect(fake.batches).toHaveLength(0);
  });
});

/** Enough of D1 to run the two statements two-way sync needs, over real SQL. */
function memoryEnv(): Env {
  const db = new DatabaseSync(":memory:");
  db.exec(
    `CREATE TABLE events (
       id text PRIMARY KEY NOT NULL,
       account_id text NOT NULL,
       device_id text NOT NULL,
       occurred_at integer NOT NULL,
       recorded_at integer NOT NULL,
       kind text NOT NULL,
       payload_json text NOT NULL,
       received_at text NOT NULL
     )`,
  );
  function bind(sql: string, params: unknown[]) {
    const statement = db.prepare(sql);
    return {
      async run() {
        const result = statement.run(...(params as never[]));
        return { meta: { changes: Number(result.changes) } };
      },
      async first<T>() {
        return (statement.get(...(params as never[])) as T | undefined) ?? null;
      },
      async all<T>() {
        return { results: statement.all(...(params as never[])) as T[] };
      },
    };
  }
  const database = {
    prepare(sql: string) {
      return { bind: (...params: unknown[]) => bind(sql, params), ...bind(sql, []) };
    },
    async batch(statements: Array<{ run(): Promise<{ meta: { changes: number } }> }>) {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      return results;
    },
  };
  return { DB: database as unknown as D1Database } as Env;
}

/** A message event, which needs no meal validation and carries opaque data. */
function message(index: number, recordedAt: number, extra: Record<string, unknown> = {}) {
  return {
    id: `0198F333-AADB-7E00-8000-00000000000${index}`,
    occurredAt: recordedAt - 500,
    recordedAt,
    payload: { kind: "message_sent" as const, data: { text: `note ${index}`, ...extra } },
  };
}

describe("two-way sync", () => {
  it("unions two devices by id and pages the account's whole log back", async () => {
    const env = memoryEnv();
    const account = "acct:one";

    // Device A writes three, device B writes two — and one of B's is a replay
    // of an id A already sent, which is the normal case: a phone re-uploads its
    // whole log at launch to repair any write that lost its network race.
    const first = await ingestEvents(env, account, {
      deviceId: "device-a-0000000000",
      events: [message(1, 1_000), message(2, 2_000), message(3, 3_000)],
    });
    expect(first).toEqual({ accepted: 3, inserted: 3, replayed: 0 });

    const second = await ingestEvents(env, account, {
      deviceId: "device-b-0000000000",
      events: [message(3, 3_000), message(4, 4_000)],
    });
    expect(second).toEqual({ accepted: 2, inserted: 1, replayed: 1 });

    // Two pages of two, then a final empty page. `cursor` is null the moment a
    // page is short, so a client that stops there sees everything exactly once.
    const pageOne = await pullEvents(env.DB, account, { limit: 2 });
    expect(pageOne.events).toHaveLength(2);
    expect(pageOne.cursor).not.toBeNull();

    const pageTwo = await pullEvents(env.DB, account, {
      limit: 2,
      after: pageOne.cursor ?? undefined,
    });
    expect(pageTwo.events).toHaveLength(2);
    expect(pageTwo.cursor).not.toBeNull();

    const pageThree = await pullEvents(env.DB, account, {
      limit: 2,
      after: pageTwo.cursor ?? undefined,
    });
    expect(pageThree.events).toEqual([]);
    expect(pageThree.cursor).toBeNull();

    const all = [...pageOne.events, ...pageTwo.events].map(
      (line) => JSON.parse(line) as { id: string; recordedAt: number; payload: unknown },
    );
    expect(all).toHaveLength(4);
    expect(new Set(all.map((event) => event.id)).size).toBe(4);
    // `(recorded_at, id)` order, which is what makes the cursor a total order.
    expect(all.map((event) => event.recordedAt)).toEqual([1_000, 2_000, 3_000, 4_000]);
  });

  it("hands back each event as the text of its envelope, unread", async () => {
    const env = memoryEnv();
    const account = "acct:one";
    // Something no schema names, inside the opaque `data` — the thing that has
    // to survive a phone pulling it and putting it back.
    const odd = { nested: { list: [1, "two", null], unicode: 'ラーメン " \\ 🍜' } };
    await ingestEvents(env, account, {
      deviceId: "device-a-0000000000",
      events: [message(1, 1_000, odd)],
    });

    const page = await pullEvents(env.DB, account, { limit: 10 });
    const [line] = page.events;
    if (!line) throw new Error("Expected one event.");
    // A string, not an object: the phone appends it to its log without parsing.
    expect(typeof line).toBe("string");
    expect(JSON.parse(line)).toEqual({
      id: "0198F333-AADB-7E00-8000-000000000001",
      occurredAt: 500,
      recordedAt: 1_000,
      payload: { kind: "message_sent", data: { text: "note 1", ...odd } },
    });

    // And it is stable under round-trip, which is the guarantee that actually
    // matters: send back what was handed over and the same string returns.
    await ingestEvents(env, account, {
      deviceId: "device-b-0000000000",
      events: [JSON.parse(line)],
    });
    expect((await pullEvents(env.DB, account, { limit: 10 })).events).toEqual([line]);
  });

  it("rejects a cursor that is not one", async () => {
    const env = memoryEnv();
    await expect(pullEvents(env.DB, "acct:one", { limit: 10, after: "nonsense" })).rejects.toThrow(
      /Invalid event cursor/,
    );
  });
});
