import { HttpError } from "./http-error";

export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([^\s]+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

/**
 * The legacy device partition an identity exchange may adopt.
 *
 * Builds before required Apple sign-in wrote under a random id kept in the
 * Keychain. Sign-in still resolves that partition so an upgraded phone's
 * history can join the verified account without rewriting stored rows.
 *
 * This is a partition, not a proof. A header can say anything, so it separates
 * honest callers from each other and does nothing against someone who wants in.
 * Quota keyed on something forgeable is a fairness mechanism; the signed-in
 * account session is the authorization boundary.
 *
 * This is never sufficient authorization for production data routes; the API
 * middleware requires a verified session. A verified
 * session resolves to an `acct:` partition and can read every device partition
 * the account has adopted (`data/accounts.ts`); a bare device id still resolves
 * to itself and reads only what it wrote, because a forgeable header must not
 * start unlocking rows it never wrote. Nothing retroactively claims that the
 * legacy `device:` rows were proved — they were not, and the merge is careful to
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
