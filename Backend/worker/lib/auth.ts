import type { Env } from "../env";
import { HttpError } from "./http-error";

export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([^\s]+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

async function digest(value: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
}

export async function tokenDigest(value: string): Promise<string> {
  const bytes = new Uint8Array(await digest(value));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function tokensMatch(provided: string, expected: string): Promise<boolean> {
  if (!provided || !expected) return false;
  const [left, right] = await Promise.all([digest(provided), digest(expected)]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  if (a.byteLength !== b.byteLength) return false;

  let difference = 0;
  for (let index = 0; index < a.byteLength; index += 1) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

/** Resolve a revocable friend token without retaining the bearer credential. */
export async function accountForInviteToken(
  database: D1Database,
  token: string,
): Promise<string | null> {
  const tokenHash = await tokenDigest(token);
  const row = await database
    .prepare(
      `SELECT account_id AS accountId
         FROM friend_invite_tokens
        WHERE token_hash = ? AND revoked_at IS NULL`,
    )
    .bind(tokenHash)
    .first<{ accountId: string }>();
  return row?.accountId ?? null;
}

/**
 * Who this request belongs to, when nobody logs in.
 *
 * With no accounts, the device is the account: it generates an id once, keeps it
 * in the Keychain, and sends it on every call. Everything already partitions by
 * `accountId` — events, evals, recognitions — so anonymous multi-user is that
 * one substitution rather than a new column anywhere.
 *
 * This is a partition, not a proof. A header can say anything, so it separates
 * honest callers from each other and does nothing against someone who wants in;
 * the shared token below is what keeps a scanner out, and App Attest is what
 * would make the id itself trustworthy. Ordering matters: quota keyed on
 * something forgeable is a fairness mechanism, and the global ceiling is the
 * only thing that bounds the bill.
 */
export function accountForDevice(request: Request): string {
  const device = request.headers.get("X-Device-Id")?.trim();
  if (device && /^[A-Za-z0-9-]{16,64}$/.test(device)) return `device:${device}`;
  // No id means sharing one bucket with every other anonymous caller, which is
  // the incentive we want.
  return `ip:${request.headers.get("CF-Connecting-IP") ?? "unknown"}`;
}

export function requireStableAccount(accountId: string): string {
  if (accountId.startsWith("ip:")) {
    throw new HttpError(400, "X-Device-Id is required for stored data.");
  }
  return accountId;
}

export async function requireAccount(
  authorizationHeader: string | undefined,
  env: Env,
  request?: Request,
): Promise<string> {
  const token = bearerToken(authorizationHeader);
  if (!token) throw new HttpError(401, "A valid invite token is required.");

  const invitedAccount = await accountForInviteToken(env.DB, token);
  if (invitedAccount) return invitedAccount;

  // Migration-only owner fallback. Friend builds never embed this secret; once
  // the owner's invite token is installed, the Worker secret can be removed.
  if (env.EATSOME_API_TOKEN && (await tokensMatch(token, env.EATSOME_API_TOKEN))) {
    return env.ACCOUNT_ID === "anonymous" && request ? accountForDevice(request) : env.ACCOUNT_ID;
  }
  throw new HttpError(401, "A valid invite token is required.");
}
