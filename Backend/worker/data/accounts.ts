import type { SignInRequest } from "../../src/contracts";
import type { Env } from "../env";
import { accountForDevice, requireStableAccount } from "../lib/auth";
import { HttpError } from "../lib/http-error";
import { type IdentityProvider, parseAudiences, verifyIdentityToken } from "../lib/identity-token";
import { uuidV7 } from "../lib/ids";

/**
 * Accounts, and the merge that gives one a device's anonymous history.
 *
 * ## Why nothing is rewritten
 *
 * The obvious merge is `UPDATE events SET account_id = 'acct:…' WHERE
 * account_id = 'device:…'`, and it is wrong here for three separate reasons,
 * any one of which would be enough.
 *
 * 1. It contradicts the storage rule the rest of the system is built on. The
 *    event log is append-only end to end — a correction is a `mealRevised`
 *    event, not an edit — precisely so that what was recorded stays readable as
 *    what was recorded. `account_id` is part of that record: it says which
 *    partition this row was written under, which is a fact about the past. An
 *    account is a fact about the present and is allowed to change.
 *
 * 2. D1 has no transaction that spans four tables and an unbounded row count.
 *    `batch()` is one implicit transaction per call, but a merge of a long
 *    history is many calls, and a Worker that is evicted between them leaves
 *    half a person's meals under the old key and half under the new. Both
 *    halves look valid. Nothing detects it. The user sees two months of missing
 *    meals and no error anywhere.
 *
 * 3. It is irreversible in the way that matters. Once the rows are rewritten,
 *    the fact that they came from a particular device is gone, so an
 *    accidental merge — the shared iPad in a household, signed into the wrong
 *    Apple ID once — cannot be unpicked even in principle.
 *
 * So the merge is one row in `account_partitions`: `device:<id>` belongs to
 * `acct:<id>`. Reading as an account reads the union of its partitions. The
 * write is a single INSERT, so it either happened or it did not; there is no
 * half-merged state to detect. Repeating it is a no-op by primary key, which is
 * what makes signing in twice free.
 *
 * The cost is one extra `IN (…)` on every read, over a set that is the number
 * of devices a person owns. That is the whole price.
 *
 * ## Where new events go
 *
 * A signed-in request writes under the *account's own* partition, `acct:<id>`,
 * not under the device's. The device partition is a closed record of what that
 * phone logged before anyone signed in; it stops growing at the moment of
 * sign-in and is only ever read again.
 *
 * This is what makes the awkward cases behave. Take the two the milestone asks
 * about:
 *
 *   - **A device signs into a second identity.** The partition stays with the
 *     first account — first link wins, by primary key. New events go to the
 *     second account's own partition, because that is who is signed in and
 *     those meals are theirs. The pre-sign-in history stays with the first
 *     account, because that is who claimed it. Nothing moves, and the endpoint
 *     says `adopted: false` so the client can tell the person their old meals
 *     stayed where they were rather than silently showing them a shorter
 *     history than they had yesterday.
 *
 *   - **A second device signs into an account that already has events.** Its
 *     own partition is unlinked, so it is adopted; that phone's anonymous
 *     history joins the union. From then on both phones write to `acct:<id>`
 *     and each pulls the union. No merge algorithm, because there is nothing to
 *     reconcile: two append-only streams concatenated and sorted by
 *     `occurredAt` is exactly what the client already does with its own log.
 *
 * ## What is irreversible
 *
 * Linking a device partition to an account. There is no unlink endpoint, and
 * there deliberately is not one: unlinking would make a person's meals vanish
 * from a phone that had been showing them, which is the failure this whole
 * design is arranged against. The link is a single row, so a support-shaped
 * reversal is possible by hand — but nothing in the API offers it, and
 * `POST /auth/sessions` says so in its own response.
 *
 * Deleting an account's data is irreversible in the ordinary way, and it now
 * spans every linked partition. That is the honest reading of "delete my data":
 * before this milestone the same call deleted one device's rows and reported
 * success, which was true and would have stopped being true the moment two
 * devices shared an account.
 */

/** 180 days. Long enough that a phone in a drawer still works; short enough
 *  that a token lifted from a backup does not outlive the app version. */
const SESSION_TTL_MS = 180 * 86_400_000;

const SESSION_HEADER = "X-Session-Token";

export type Principal = {
  /**
   * The partition new rows are written under. `acct:<id>` when signed in,
   * `device:<id>` (or `ip:<addr>`) when not — so every existing call site keeps
   * working unchanged, because it was already a partition string.
   */
  accountId: string;
  /** Every partition this caller may read. Always contains `accountId`. */
  partitions: string[];
  signedIn: boolean;
};

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function audiencesFor(env: Env, provider: IdentityProvider): string[] {
  return parseAudiences(provider === "apple" ? env.APPLE_CLIENT_IDS : env.GOOGLE_CLIENT_IDS);
}

/** The union an account reads over. The account's own partition is implicit —
 *  it is never in `account_partitions`, because it is not a device. */
export async function partitionsFor(database: D1Database, accountId: string): Promise<string[]> {
  const rows = await database
    .prepare("SELECT partition_id AS partitionId FROM account_partitions WHERE account_id = ?")
    .bind(accountId)
    .all<{ partitionId: string }>();
  const partitions = new Set<string>([accountId]);
  for (const row of rows.results) partitions.add(row.partitionId);
  return [...partitions];
}

/**
 * Provider subject to account, creating the account the first time.
 *
 * `attachTo` is the account of the session the caller already holds, if any.
 * That is how the second provider lands on the right account: nothing in an
 * Apple token and a Google token says the two subjects are the same person, so
 * the only honest evidence that they are is somebody signing in with the second
 * while already signed in with the first. Without it, "Sign in with Google" on
 * a phone that signed in with Apple last week is a different person as far as
 * the server can tell, and quietly guessing otherwise on a matching email is
 * how one Gmail address inherits a stranger's food diary.
 */
async function accountForIdentity(
  database: D1Database,
  identity: { provider: IdentityProvider; subject: string; email: string | null },
  emailVerified: boolean,
  now: number,
  attachTo: string | null,
): Promise<{ accountId: string; created: boolean }> {
  const lookup = database
    .prepare("SELECT account_id AS accountId FROM identities WHERE provider = ? AND subject = ?")
    .bind(identity.provider, identity.subject);

  const existing = await lookup.first<{ accountId: string }>();
  // An identity that already belongs somewhere keeps belonging there, even when
  // the caller holds a session for a different account. Re-pointing it would be
  // a rewrite, and the account it was moved off would lose a way back in.
  if (existing) return { accountId: existing.accountId, created: false };

  if (attachTo) {
    await database
      .prepare(
        `INSERT INTO identities (provider, subject, account_id, email, email_verified, created_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(provider, subject) DO NOTHING`,
      )
      .bind(
        identity.provider,
        identity.subject,
        attachTo,
        identity.email,
        emailVerified ? 1 : 0,
        now,
      )
      .run();
    const settled = await lookup.first<{ accountId: string }>();
    return { accountId: settled?.accountId ?? attachTo, created: false };
  }

  const candidate = `acct:${uuidV7(now)}`;
  // One batch, so the account row and the identity that justifies it land in
  // the same implicit transaction. The identity insert is the one that can
  // lose: two phones signing into the same Apple ID at the same second both
  // reach here, and exactly one row survives the primary key.
  await database.batch([
    database
      .prepare("INSERT INTO accounts (id, created_at) VALUES (?, ?) ON CONFLICT(id) DO NOTHING")
      .bind(candidate, now),
    database
      .prepare(
        `INSERT INTO identities (provider, subject, account_id, email, email_verified, created_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(provider, subject) DO NOTHING`,
      )
      .bind(
        identity.provider,
        identity.subject,
        candidate,
        identity.email,
        emailVerified ? 1 : 0,
        now,
      ),
  ]);

  const settled = await lookup.first<{ accountId: string }>();
  const accountId = settled?.accountId ?? candidate;
  if (accountId !== candidate) {
    // We lost the race. Our account row is seconds old, has no identity, no
    // partition and no events, and nothing can ever reach it — but an account
    // table that accumulates unreachable rows is a table nobody can reason
    // about later, so it goes. The guard makes this safe to run concurrently
    // with the winner: it only deletes an account with nothing pointing at it.
    await database
      .prepare(
        `DELETE FROM accounts
          WHERE id = ?
            AND NOT EXISTS (SELECT 1 FROM identities WHERE account_id = accounts.id)
            AND NOT EXISTS (SELECT 1 FROM account_partitions WHERE account_id = accounts.id)`,
      )
      .bind(candidate)
      .run();
  }
  return { accountId, created: accountId === candidate };
}

export type MergeOutcome = {
  /** The device partition this sign-in tried to hand over. */
  partition: string;
  /** True when the partition belongs to this account — now, or from before. */
  adopted: boolean;
  /** Set when the partition already belonged to somebody else. */
  conflict: "linked_to_another_account" | null;
};

async function adoptPartition(
  database: D1Database,
  partition: string,
  accountId: string,
  now: number,
): Promise<MergeOutcome> {
  await database
    .prepare(
      `INSERT INTO account_partitions (partition_id, account_id, linked_at)
       VALUES (?, ?, ?)
       ON CONFLICT(partition_id) DO NOTHING`,
    )
    .bind(partition, accountId, now)
    .run();

  // Read back rather than trusting `meta.changes`. Zero changes means either
  // "already ours" or "already someone else's", and those are opposite answers
  // to give the person signing in.
  const owner = await database
    .prepare("SELECT account_id AS accountId FROM account_partitions WHERE partition_id = ?")
    .bind(partition)
    .first<{ accountId: string }>();
  const adopted = owner?.accountId === accountId;
  return { partition, adopted, conflict: adopted ? null : "linked_to_another_account" };
}

export type SignInResult = {
  accountId: string;
  sessionToken: string;
  expiresAt: number;
  /** True the first time this provider subject was ever seen. */
  accountCreated: boolean;
  merge: MergeOutcome;
};

/**
 * A deployment with `ACCOUNT_ID` set to something other than `anonymous` is
 * pinned to one partition on purpose — a personal instance, or an eval run. It
 * has one user by configuration, so there is nothing for a sign-in to decide,
 * and quietly accepting one would mint sessions that never resolve to anything.
 */
function pinnedPrincipal(env: Env): Principal {
  return { accountId: env.ACCOUNT_ID, partitions: [env.ACCOUNT_ID], signedIn: false };
}

export async function signIn(
  env: Env,
  request: Request,
  input: SignInRequest,
): Promise<SignInResult> {
  if (env.ACCOUNT_ID !== "anonymous") {
    throw new HttpError(409, "This deployment is pinned to a single account.");
  }
  const provider = input.provider;
  const identity = await verifyIdentityToken(provider, input.identityToken, {
    audiences: audiencesFor(env, provider),
    nonce: input.nonce,
  });

  // Refused for the same reason writes are: an IP-keyed partition changes when
  // the phone changes network, so adopting one would attach a stranger's rows
  // to this account the next time that address is reused.
  const partition = requireStableAccount(accountForDevice(request));

  // A caller who is already signed in is adding a second provider to the
  // account they are holding, not starting a new one. An expired or forged
  // session token throws here rather than silently becoming a fresh account.
  const current = await resolvePrincipal(env, request);

  const now = Date.now();
  const { accountId, created } = await accountForIdentity(
    env.DB,
    identity,
    identity.emailVerified,
    now,
    current.signedIn ? current.accountId : null,
  );
  const merge = await adoptPartition(env.DB, partition, accountId, now);

  // 256 bits from the CSPRNG. Only its digest is stored, so this is the last
  // moment the plaintext exists on the server.
  const raw = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const expiresAt = now + SESSION_TTL_MS;
  await env.DB.prepare(
    `INSERT INTO sessions (token_hash, account_id, device_id, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(await sha256Hex(raw), accountId, partition, now, expiresAt)
    .run();

  return { accountId, sessionToken: raw, expiresAt, accountCreated: created, merge };
}

/**
 * Who this request is, before anything else runs.
 *
 * With no session header the answer is exactly what it was before accounts
 * existed, down to the string: the device partition, reading only itself. That
 * is deliberate. A device id is a header anyone can copy, and it stayed
 * acceptable while it only ever unlocked the rows that same header had written.
 * Serving the account union to a bare device id would quietly turn a guessed
 * header into every device that account owns.
 *
 * A session token that has expired or been revoked is a 401, never a fall back
 * to the device. A client that believes it is signed in and is silently
 * downgraded writes its next month of meals into the wrong partition and finds
 * out when someone opens the other phone.
 */
export async function resolvePrincipal(env: Env, request: Request): Promise<Principal> {
  if (env.ACCOUNT_ID !== "anonymous") return pinnedPrincipal(env);
  const token = request.headers.get(SESSION_HEADER)?.trim();
  if (!token) {
    const device = accountForDevice(request);
    return { accountId: device, partitions: [device], signedIn: false };
  }
  const session = await env.DB.prepare(
    "SELECT account_id AS accountId FROM sessions WHERE token_hash = ? AND expires_at > ?",
  )
    .bind(await sha256Hex(token), Date.now())
    .first<{ accountId: string }>();
  if (!session) throw new HttpError(401, "This sign-in has expired. Sign in again.");
  return {
    accountId: session.accountId,
    partitions: await partitionsFor(env.DB, session.accountId),
    signedIn: true,
  };
}

/** Sign out this device. Other devices keep their sessions, and the partition
 *  link is untouched — signing out is not un-merging. */
export async function revokeSession(env: Env, request: Request): Promise<{ revoked: number }> {
  const token = request.headers.get(SESSION_HEADER)?.trim();
  if (!token) return { revoked: 0 };
  const result = await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?")
    .bind(await sha256Hex(token))
    .run();
  return { revoked: result.meta.changes ?? 0 };
}

/** Weekly, with the orphan sweeps. An expired row is already refused by
 *  `resolvePrincipal`; this is hygiene, not enforcement. */
export async function deleteExpiredSessions(env: Env, now = Date.now()): Promise<number> {
  const result = await env.DB.prepare("DELETE FROM sessions WHERE expires_at <= ?").bind(now).run();
  return result.meta.changes ?? 0;
}
