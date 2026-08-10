import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import type { VerifiedIdentity } from "../lib/identity-token";

/**
 * The merge is the part of this milestone with no second chance, so it is
 * tested against a real SQLite rather than a mock: the primary keys, the
 * `ON CONFLICT DO NOTHING` and the foreign keys are the mechanism, and a fake
 * that agrees with the code by construction would prove nothing about any of
 * them. `node:sqlite` ships with the runtime and D1 is SQLite, so the shim
 * below is only the D1 method names.
 *
 * The signature check is somebody else's test — this file stubs verification
 * and asks what happens to a person's history once a `sub` is established.
 */

vi.mock("../lib/identity-token", async (importOriginal) => {
  const original = await importOriginal<typeof import("../lib/identity-token")>();
  return {
    ...original,
    verifyIdentityToken: vi.fn(
      async (provider: "apple" | "google", token: string): Promise<VerifiedIdentity> => ({
        provider,
        // The stub's contract: the token *is* the subject. Every test below
        // therefore names the identity it is signing in as, in the call.
        subject: token,
        email: null,
        emailVerified: true,
        expiresAt: Date.now() + 600_000,
      }),
    ),
  };
});

const { partitionsFor, resolvePrincipal, revokeSession, signIn } = await import("./accounts");

type Bound = {
  run(): Promise<{ meta: { changes: number } }>;
  first<T>(): Promise<T | null>;
  all<T>(): Promise<{ results: T[] }>;
};

/** Just enough of D1 to run the statements in `accounts.ts`. */
function memoryD1(): D1Database {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys = ON");

  // The real migration, not a copy of it: a schema that drifts from what D1
  // actually runs is a test that passes on a database nobody has. Relative to
  // the vitest root, which is this package.
  const migration = readFileSync("migrations/0007_accounts_and_identities.sql", "utf8");
  for (const statement of migration.split("--> statement-breakpoint")) {
    const trimmed = statement.trim();
    if (trimmed) db.exec(trimmed);
  }
  // Enough of `events` to prove that a merge leaves stored rows alone.
  db.exec(
    `CREATE TABLE events (
       id text PRIMARY KEY NOT NULL,
       account_id text NOT NULL,
       recorded_at integer NOT NULL
     )`,
  );

  function bind(sql: string, params: unknown[]): Bound {
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
      return {
        bind: (...params: unknown[]) => bind(sql, params),
        ...bind(sql, []),
      };
    },
    async batch(statements: Bound[]) {
      db.exec("BEGIN");
      try {
        const results = [];
        for (const statement of statements) results.push(await statement.run());
        db.exec("COMMIT");
        return results;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
    raw: () => db,
  };
  return database as unknown as D1Database;
}

function envFor(database: D1Database): Env {
  return { DB: database, ACCOUNT_ID: "anonymous", APPLE_CLIENT_IDS: "app.shaman.tracker" } as Env;
}

function requestFrom(deviceId: string, sessionToken?: string): Request {
  const headers = new Headers({ "X-Device-Id": deviceId });
  if (sessionToken) headers.set("X-Session-Token", sessionToken);
  return new Request("https://api.test/api/v1/auth/sessions", { headers });
}

const PHONE = "AAAAAAAA-BBBB-CCCC-DDDD-000000000001";
const TABLET = "AAAAAAAA-BBBB-CCCC-DDDD-000000000002";

function logEvent(database: D1Database, id: string, partition: string): Promise<unknown> {
  return database
    .prepare("INSERT INTO events (id, account_id, recorded_at) VALUES (?, ?, ?)")
    .bind(id, partition, 1)
    .run();
}

function partitionOf(database: D1Database, eventId: string): Promise<{ accountId: string } | null> {
  return database
    .prepare("SELECT account_id AS accountId FROM events WHERE id = ?")
    .bind(eventId)
    .first<{ accountId: string }>();
}

describe("account merge", () => {
  let database: D1Database;
  let env: Env;

  beforeEach(() => {
    database = memoryD1();
    env = envFor(database);
  });

  it("adopts the device's anonymous history without moving a single row", async () => {
    await logEvent(database, "event-before-sign-in", `device:${PHONE}`);

    const result = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    expect(result.accountId).toMatch(/^acct:/);
    expect(result.accountCreated).toBe(true);
    expect(result.merge).toEqual({ partition: `device:${PHONE}`, adopted: true, conflict: null });

    // The point of the whole design: the stored row still says where it was
    // written. If this ever reads `acct:…`, the merge became a rewrite.
    expect(await partitionOf(database, "event-before-sign-in")).toEqual({
      accountId: `device:${PHONE}`,
    });
    // And the account can read it anyway, through the union.
    expect((await partitionsFor(database, result.accountId)).sort()).toEqual(
      [result.accountId, `device:${PHONE}`].sort(),
    );
  });

  it("is free to repeat: signing in twice changes nothing but the session", async () => {
    const first = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const second = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    expect(second.accountId).toBe(first.accountId);
    expect(second.accountCreated).toBe(false);
    expect(second.merge.adopted).toBe(true);
    expect(second.sessionToken).not.toBe(first.sessionToken);
    // Both sessions keep working. A retry must not sign the first device out.
    for (const token of [first.sessionToken, second.sessionToken]) {
      const principal = await resolvePrincipal(env, requestFrom(PHONE, token));
      expect(principal.accountId).toBe(first.accountId);
    }
    const links = await database
      .prepare("SELECT COUNT(*) AS n FROM account_partitions")
      .first<{ n: number }>();
    expect(links?.n).toBe(1);
  });

  it("joins a second device to the account and reads the union", async () => {
    await logEvent(database, "from-the-phone", `device:${PHONE}`);
    await logEvent(database, "from-the-tablet", `device:${TABLET}`);

    const phone = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const tablet = await signIn(env, requestFrom(TABLET), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    expect(tablet.accountId).toBe(phone.accountId);
    expect(tablet.merge.adopted).toBe(true);
    const principal = await resolvePrincipal(env, requestFrom(TABLET, tablet.sessionToken));
    expect(principal.signedIn).toBe(true);
    expect(principal.partitions.sort()).toEqual(
      [phone.accountId, `device:${PHONE}`, `device:${TABLET}`].sort(),
    );
    // New events from either device land on the account's own partition, so the
    // device partitions stop growing at the moment of sign-in.
    expect(principal.accountId).toBe(phone.accountId);
  });

  it("adds a second provider to the account whose session the caller holds", async () => {
    const apple = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    // Nothing in an Apple token and a Google token says the two subjects are
    // the same human. Holding the Apple session while presenting the Google
    // token is the evidence, and it is the only evidence we accept — matching
    // on email address is how one Gmail inherits a stranger's diary.
    const google = await signIn(env, requestFrom(PHONE, apple.sessionToken), {
      provider: "google",
      identityToken: "google-subject-1",
    });
    expect(google.accountId).toBe(apple.accountId);
    expect(google.accountCreated).toBe(false);
    const identities = await database
      .prepare("SELECT COUNT(*) AS n FROM identities WHERE account_id = ?")
      .bind(apple.accountId)
      .first<{ n: number }>();
    expect(identities?.n).toBe(2);
  });

  it("makes a second provider on a signed-out device its own account", async () => {
    const apple = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const google = await signIn(env, requestFrom(PHONE), {
      provider: "google",
      identityToken: "google-subject-1",
    });
    expect(google.accountId).not.toBe(apple.accountId);
    expect(google.merge).toEqual({
      partition: `device:${PHONE}`,
      adopted: false,
      conflict: "linked_to_another_account",
    });
  });

  it("never re-points an identity that already belongs to an account", async () => {
    const first = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const second = await signIn(env, requestFrom(TABLET), {
      provider: "apple",
      identityToken: "apple-subject-2",
    });
    // Signed in as the second, presenting the first's token: this is a switch,
    // not a takeover. Moving the identity would strip the first account of the
    // only way back into it.
    const switched = await signIn(env, requestFrom(TABLET, second.sessionToken), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    expect(switched.accountId).toBe(first.accountId);
  });

  it("refuses to move a device's history to a second identity", async () => {
    await logEvent(database, "logged-by-the-first-owner", `device:${PHONE}`);
    const first = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const second = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-2",
    });

    expect(second.accountId).not.toBe(first.accountId);
    expect(second.merge.conflict).toBe("linked_to_another_account");
    // The history stays with whoever claimed it first, and the second account
    // starts empty rather than inheriting a stranger's meals.
    expect(await partitionsFor(database, first.accountId)).toContain(`device:${PHONE}`);
    expect(await partitionsFor(database, second.accountId)).toEqual([second.accountId]);
  });

  it("leaves an unknown or expired session as a refusal, never as a downgrade", async () => {
    const session = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    // Silently falling back to the device partition is the failure this guards:
    // the client keeps writing, believing it is signed in, into the wrong place.
    await expect(resolvePrincipal(env, requestFrom(PHONE, "not-a-session"))).rejects.toMatchObject({
      status: 401,
    });

    await database
      .prepare("UPDATE sessions SET expires_at = ? WHERE account_id = ?")
      .bind(Date.now() - 1, session.accountId)
      .run();
    await expect(
      resolvePrincipal(env, requestFrom(PHONE, session.sessionToken)),
    ).rejects.toMatchObject({ status: 401 });
  });

  it("gives a caller with no session exactly what it had before accounts existed", async () => {
    await signIn(env, requestFrom(PHONE), { provider: "apple", identityToken: "apple-subject-1" });
    const principal = await resolvePrincipal(env, requestFrom(PHONE));
    // A linked device id is still just a device id. Serving the union here
    // would turn a copyable header into the whole account.
    expect(principal).toEqual({
      accountId: `device:${PHONE}`,
      partitions: [`device:${PHONE}`],
      signedIn: false,
    });
  });

  it("stores a session's digest and never the token", async () => {
    const session = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const row = await database
      .prepare("SELECT token_hash AS hash FROM sessions LIMIT 1")
      .first<{ hash: string }>();
    expect(row?.hash).toMatch(/^[a-f0-9]{64}$/);
    expect(row?.hash).not.toBe(session.sessionToken);
  });

  it("signs one device out without un-merging anything", async () => {
    const session = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    expect(await revokeSession(env, requestFrom(PHONE, session.sessionToken))).toEqual({
      revoked: 1,
    });
    await expect(
      resolvePrincipal(env, requestFrom(PHONE, session.sessionToken)),
    ).rejects.toMatchObject({ status: 401 });
    // The adopted history is still the account's.
    expect(await partitionsFor(database, session.accountId)).toContain(`device:${PHONE}`);
  });

  it("refuses a caller with no usable device id", async () => {
    const anonymous = new Request("https://api.test/api/v1/auth/sessions");
    await expect(
      signIn(env, anonymous, { provider: "apple", identityToken: "apple-subject-1" }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("refuses sign-in on a deployment pinned to one account", async () => {
    const pinned = { ...envFor(database), ACCOUNT_ID: "solo" } as Env;
    await expect(
      signIn(pinned, requestFrom(PHONE), { provider: "apple", identityToken: "apple-subject-1" }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await resolvePrincipal(pinned, requestFrom(PHONE))).toEqual({
      accountId: "solo",
      partitions: ["solo"],
      signedIn: false,
    });
  });
});
