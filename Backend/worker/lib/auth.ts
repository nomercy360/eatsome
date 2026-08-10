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
 *
 * Signing in adds the proof beside this rather than on top of it. A verified
 * session resolves to an `acct:` partition and can read every device partition
 * the account has adopted (`data/accounts.ts`); a bare device id still resolves
 * to itself and reads only what it wrote, because a forgeable header must not
 * start unlocking rows it never wrote. Nothing retroactively claims that the
 * old `device:` rows were proved — they were not, and the merge is careful to
 * leave them saying exactly what they said.
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

/**
 * The token says "this is the app", and nothing more than that.
 *
 * Who the caller is comes afterwards, from `resolvePrincipal`: the device id
 * says which copy of the app, and a session token says which person. Splitting
 * the two apart is what lets a signed-in request keep the same shared-token
 * gate as every other one.
 */
export async function requireAppToken(
  authorizationHeader: string | undefined,
  env: Env,
): Promise<void> {
  const token = bearerToken(authorizationHeader);
  if (!token || !(await tokensMatch(token, env.EATSOME_API_TOKEN))) {
    throw new HttpError(401, "A valid bearer token is required.");
  }
}
