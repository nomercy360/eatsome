import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import type { VerifiedIdentity } from "../lib/identity-token";

/**
 * Accounts against a real SQLite rather than a mock: the primary keys, the
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
      async (provider: "apple", token: string): Promise<VerifiedIdentity> => ({
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

const { requireAuthenticatedPrincipal, revokeSession, signIn } = await import("./accounts");

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
  // actually runs is a test that passes on a database nobody has.
  const migration = readFileSync(
    join(import.meta.dirname, "../../migrations/0000_init.sql"),
    "utf8",
  );
  for (const statement of migration.split("--> statement-breakpoint")) {
    const trimmed = statement.trim();
    if (trimmed) db.exec(trimmed);
  }

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
  };
  return database as unknown as D1Database;
}

function envFor(database: D1Database): Env {
  return { DB: database, ACCOUNT_ID: "anonymous", APPLE_CLIENT_IDS: "app.shaman.tracker" } as Env;
}

function requestFrom(deviceId: string, sessionToken?: string): Request {
  const headers = new Headers({ "X-Device-Id": deviceId });
  if (sessionToken) headers.set("Authorization", `Bearer ${sessionToken}`);
  return new Request("https://api.test/api/v1/auth/sessions", { headers });
}

const PHONE = "AAAAAAAA-BBBB-CCCC-DDDD-000000000001";
const TABLET = "AAAAAAAA-BBBB-CCCC-DDDD-000000000002";

function logEvent(database: D1Database, id: string, accountId: string): Promise<unknown> {
  return database
    .prepare(
      `INSERT INTO events
        (id, account_id, device_id, occurred_at, recorded_at, kind, payload_json, received_at)
       VALUES (?, ?, 'test', 1, 1, 'message_sent', '{}', '2026-08-16T00:00:00Z')`,
    )
    .bind(id, accountId)
    .run();
}

describe("accounts", () => {
  let database: D1Database;
  let env: Env;

  beforeEach(() => {
    database = memoryD1();
    env = envFor(database);
  });

  it("mints one account for a subject and returns a usable session", async () => {
    const result = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    expect(result.accountId).toMatch(/^acct:/);
    expect(result.accountCreated).toBe(true);
    expect(result.expiresAt).toBeGreaterThan(Date.now());
    // Exactly the four fields the client decodes. `merge` went with the device
    // partitions it described.
    expect(Object.keys(result).sort()).toEqual([
      "accountCreated",
      "accountId",
      "expiresAt",
      "sessionToken",
    ]);

    const principal = await requireAuthenticatedPrincipal(
      env,
      requestFrom(PHONE, result.sessionToken),
    );
    expect(principal).toEqual({ accountId: result.accountId, deviceId: PHONE });
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
    expect(second.sessionToken).not.toBe(first.sessionToken);
    // Both sessions keep working. A retry must not sign the first device out.
    for (const token of [first.sessionToken, second.sessionToken]) {
      const principal = await requireAuthenticatedPrincipal(env, requestFrom(PHONE, token));
      expect(principal.accountId).toBe(first.accountId);
    }
  });

  it("gives a second device the same account, and so the same rows", async () => {
    // The whole of multi-device now: two sessions, one `account_id`. Reading is
    // one equality rather than a union over adopted device partitions, and a
    // phone that signs in sees what the other phone uploaded because the rows
    // were written under the account in the first place.
    const phone = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    await logEvent(database, "from-the-phone", phone.accountId);

    const tablet = await signIn(env, requestFrom(TABLET), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    expect(tablet.accountId).toBe(phone.accountId);

    const principal = await requireAuthenticatedPrincipal(
      env,
      requestFrom(TABLET, tablet.sessionToken),
    );
    expect(principal.accountId).toBe(phone.accountId);
    expect(principal.deviceId).toBe(TABLET);
  });

  it("keeps two subjects apart", async () => {
    const first = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const second = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-2",
    });
    expect(second.accountId).not.toBe(first.accountId);
    expect(second.accountCreated).toBe(true);
  });

  it("leaves an unknown or expired session as a refusal, never as a downgrade", async () => {
    const session = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    // Silently falling back to a device-keyed identity is the failure this
    // guards: the client keeps writing, believing it is signed in, somewhere
    // nobody will look again.
    await expect(
      requireAuthenticatedPrincipal(env, requestFrom(PHONE, "not-a-session")),
    ).rejects.toMatchObject({ status: 401 });
    await expect(requireAuthenticatedPrincipal(env, requestFrom(PHONE))).rejects.toMatchObject({
      status: 401,
    });

    await database
      .prepare("UPDATE sessions SET expires_at = ? WHERE account_id = ?")
      .bind(Date.now() - 1, session.accountId)
      .run();
    await expect(
      requireAuthenticatedPrincipal(env, requestFrom(PHONE, session.sessionToken)),
    ).rejects.toMatchObject({ status: 401 });
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

  it("signs one device out and leaves the other signed in", async () => {
    const phone = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    const tablet = await signIn(env, requestFrom(TABLET), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });

    expect(await revokeSession(env, requestFrom(PHONE, phone.sessionToken))).toEqual({
      revoked: 1,
    });
    await expect(
      requireAuthenticatedPrincipal(env, requestFrom(PHONE, phone.sessionToken)),
    ).rejects.toMatchObject({ status: 401 });
    await expect(
      requireAuthenticatedPrincipal(env, requestFrom(TABLET, tablet.sessionToken)),
    ).resolves.toMatchObject({ accountId: tablet.accountId });
  });

  it("signs in from a phone that sends no device id", async () => {
    // The header is a label now, not a partition key, so its absence is a
    // nameless session rather than a refusal. It used to be a 400 because a
    // missing id meant rows would land in an `ip:`-keyed bucket that changes
    // when the phone changes network.
    const anonymous = new Request("https://api.test/api/v1/auth/sessions");
    const result = await signIn(env, anonymous, {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    expect(result.accountId).toMatch(/^acct:/);
    const row = await database
      .prepare("SELECT device_id AS deviceId FROM sessions LIMIT 1")
      .first<{ deviceId: string }>();
    expect(row?.deviceId).toBe("unknown");
  });

  it("refuses sign-in on a deployment pinned to one account", async () => {
    const pinned = { ...envFor(database), ACCOUNT_ID: "solo" } as Env;
    await expect(
      signIn(pinned, requestFrom(PHONE), { provider: "apple", identityToken: "apple-subject-1" }),
    ).rejects.toMatchObject({ status: 409 });
    await expect(requireAuthenticatedPrincipal(pinned, requestFrom(PHONE))).resolves.toEqual({
      accountId: "solo",
      deviceId: PHONE,
    });
  });
});

describe("erasure", () => {
  it("removes every row the account owns, identity last", async () => {
    const database = memoryD1();
    const env = {
      ...envFor(database),
      MEDIA: { list: async () => ({ objects: [] }) },
    } as unknown as Env;
    const { deleteAccountData } = await import("./accounts");

    const session = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    await logEvent(database, "a-meal", session.accountId);

    const result = await deleteAccountData(env, session.accountId);
    expect(result.events).toBe(1);

    for (const table of ["events", "sessions", "identities", "accounts"]) {
      const row = await database
        .prepare(`SELECT COUNT(*) AS n FROM ${table}`)
        .first<{ n: number }>();
      expect(row?.n, table).toBe(0);
    }

    // The next sign-in is a first sign-in. Leaving `identities` behind would
    // resolve it to an account whose data is gone but whose id is the same —
    // a deleted account quietly coming back as an empty one.
    const again = await signIn(env, requestFrom(PHONE), {
      provider: "apple",
      identityToken: "apple-subject-1",
    });
    expect(again.accountCreated).toBe(true);
    expect(again.accountId).not.toBe(session.accountId);
  });
});
