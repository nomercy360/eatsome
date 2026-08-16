import type { SignInRequest } from "../../src/contracts";
import type { Env } from "../env";
import { bearerToken, deviceIdFor } from "../lib/auth";
import { HttpError } from "../lib/http-error";
import { type IdentityProvider, parseAudiences, verifyIdentityToken } from "../lib/identity-token";
import { uuidV7 } from "../lib/ids";
import { deleteAccountMedia } from "./media";

/**
 * Accounts, and the whole of what one is.
 *
 * An account is `acct:<uuidv7>`, it is what every stored row's `account_id`
 * says, and every read is `WHERE account_id = ?` against exactly that string.
 *
 * It was not always. Rows used to be written under `device:<uuid>` before
 * anyone signed in, an account adopted device partitions permanently at first
 * sign-in, and every read was a union over the set — with a `merge` outcome in
 * the sign-in response saying whether the adoption had happened or collided
 * with another account. That existed to carry pre-sign-in history across the
 * introduction of required sign-in. There is no such history: sign-in is
 * required from the first launch of this build, so a device partition is a
 * place nothing is ever written, and a union over one element is an `IN` clause
 * pretending to be a policy.
 *
 * What survives from that design is the rule it was built to protect:
 * `account_id` on a stored row is a fact about where the row was written and is
 * not ours to revise. Nothing here rewrites one; the account it names is the
 * account it was written under, for good.
 */

/** 180 days. Long enough that a phone in a drawer still works; short enough
 *  that a token lifted from a backup does not outlive the app version. */
const SESSION_TTL_MS = 180 * 86_400_000;

export type Principal = {
  accountId: string;
  /** Which phone is asking. A label on the session and on stored events; it
   *  proves nothing and unlocks nothing. */
  deviceId: string;
};

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function audiencesFor(env: Env, _provider: IdentityProvider): string[] {
  return parseAudiences(env.APPLE_CLIENT_IDS);
}

/**
 * Provider subject to account, creating the account the first time.
 *
 * An identity that already belongs somewhere keeps belonging there. Re-pointing
 * it would be a rewrite, and the account it was moved off would lose its only
 * way back in.
 */
async function accountForIdentity(
  database: D1Database,
  identity: { provider: IdentityProvider; subject: string; email: string | null },
  emailVerified: boolean,
  now: number,
): Promise<{ accountId: string; created: boolean }> {
  const lookup = database
    .prepare("SELECT account_id AS accountId FROM identities WHERE provider = ? AND subject = ?")
    .bind(identity.provider, identity.subject);

  const existing = await lookup.first<{ accountId: string }>();
  if (existing) return { accountId: existing.accountId, created: false };

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
    // We lost the race. Our account row is seconds old, has no identity and no
    // events, and nothing can ever reach it — but an account table that
    // accumulates unreachable rows is a table nobody can reason about later, so
    // it goes. The guard makes this safe to run concurrently with the winner:
    // it only deletes an account with nothing pointing at it.
    await database
      .prepare(
        `DELETE FROM accounts
          WHERE id = ?
            AND NOT EXISTS (SELECT 1 FROM identities WHERE account_id = accounts.id)`,
      )
      .bind(candidate)
      .run();
  }
  return { accountId, created: accountId === candidate };
}

export type SignInResult = {
  accountId: string;
  sessionToken: string;
  expiresAt: number;
  /** True the first time this provider subject was ever seen. */
  accountCreated: boolean;
};

/**
 * A deployment with `ACCOUNT_ID` set to something other than `anonymous` is
 * pinned to one account on purpose — a personal instance, or an eval run. It
 * has one user by configuration, so there is nothing for a sign-in to decide,
 * and quietly accepting one would mint sessions that never resolve to anything.
 */
function pinnedPrincipal(env: Env, request: Request): Principal {
  return { accountId: env.ACCOUNT_ID, deviceId: deviceIdFor(request) };
}

export async function signIn(
  env: Env,
  request: Request,
  input: SignInRequest,
): Promise<SignInResult> {
  if (env.ACCOUNT_ID !== "anonymous") {
    throw new HttpError(409, "This deployment is pinned to a single account.");
  }
  const identity = await verifyIdentityToken(input.provider, input.identityToken, {
    audiences: audiencesFor(env, input.provider),
    nonce: input.nonce,
  });

  const now = Date.now();
  const { accountId, created } = await accountForIdentity(
    env.DB,
    identity,
    identity.emailVerified,
    now,
  );

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
    .bind(await sha256Hex(raw), accountId, deviceIdFor(request), now, expiresAt)
    .run();

  return { accountId, sessionToken: raw, expiresAt, accountCreated: created };
}

/**
 * Who this request is.
 *
 * A session token that has expired or been revoked is a 401, never a fall back
 * to anything. A client that believes it is signed in and is silently
 * downgraded writes its next month of meals somewhere else and finds out when
 * someone opens the other phone.
 */
export async function requireAuthenticatedPrincipal(
  env: Env,
  request: Request,
): Promise<Principal> {
  if (env.ACCOUNT_ID !== "anonymous") return pinnedPrincipal(env, request);
  const token = bearerToken(request.headers.get("Authorization") ?? undefined);
  if (!token) throw new HttpError(401, "Sign in with Apple to use eatsome.");
  const session = await env.DB.prepare(
    "SELECT account_id AS accountId FROM sessions WHERE token_hash = ? AND expires_at > ?",
  )
    .bind(await sha256Hex(token), Date.now())
    .first<{ accountId: string }>();
  if (!session) throw new HttpError(401, "This sign-in has expired. Sign in again.");
  return { accountId: session.accountId, deviceId: deviceIdFor(request) };
}

/** Sign out this device. Other devices keep their sessions. */
export async function revokeSession(env: Env, request: Request): Promise<{ revoked: number }> {
  const token = bearerToken(request.headers.get("Authorization") ?? undefined);
  if (!token) return { revoked: 0 };
  const result = await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?")
    .bind(await sha256Hex(token))
    .run();
  return { revoked: result.meta.changes ?? 0 };
}

/** Weekly, with the orphan sweep. An expired row is already refused by
 *  `requireAuthenticatedPrincipal`; this is hygiene, not enforcement. */
export async function deleteExpiredSessions(env: Env, now = Date.now()): Promise<number> {
  const result = await env.DB.prepare("DELETE FROM sessions WHERE expires_at <= ?").bind(now).run();
  return result.meta.changes ?? 0;
}

/**
 * Erasure: both R2 and every D1 row the account owns.
 *
 * The identity row goes too, and last. Leaving it behind would resolve a later
 * sign-in to an account whose data is gone but whose id is the same, which is a
 * deleted account quietly coming back as an empty one; the person asked to be
 * forgotten, so the next sign-in should be a first sign-in.
 *
 * It lived in `data/corpus.ts` while the corpus existed, which meant deleting
 * an account went through a research-dataset module. The corpus is gone and
 * this belongs where accounts do.
 */
export async function deleteAccountData(
  env: Env,
  accountId: string,
): Promise<{ mediaObjects: number; events: number }> {
  const mediaObjects = await deleteAccountMedia(env, accountId);
  const results = await env.DB.batch([
    env.DB.prepare("DELETE FROM meal_media WHERE account_id = ?").bind(accountId),
    env.DB.prepare("DELETE FROM recognitions WHERE account_id = ?").bind(accountId),
    env.DB.prepare("DELETE FROM media_objects WHERE account_id = ?").bind(accountId),
    env.DB.prepare("DELETE FROM events WHERE account_id = ?").bind(accountId),
    // Order matters against the foreign keys: sessions and identities both
    // point at `accounts`, so the account row can only go last.
    env.DB.prepare("DELETE FROM sessions WHERE account_id = ?").bind(accountId),
    env.DB.prepare("DELETE FROM identities WHERE account_id = ?").bind(accountId),
    env.DB.prepare("DELETE FROM accounts WHERE id = ?").bind(accountId),
  ]);
  return { mediaObjects, events: results[3]?.meta.changes ?? 0 };
}
