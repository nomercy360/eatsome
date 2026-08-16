export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([^\s]+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

/**
 * Which phone is calling, for the record and for nothing else.
 *
 * `X-Device-Id` used to be a partition key: rows were written under
 * `device:<id>` before anyone signed in, and an account read the union of every
 * device it had adopted. That machinery is gone — an account is `acct:<id>` and
 * every read is one equality — so a copyable header now decides exactly two
 * things, both of them labels: which session row to revoke at sign-out, and
 * which phone a stored event came from.
 *
 * It authorizes nothing and it keys no quota. Rate limits key on the verified
 * account, because a fairness bucket attached to a header anybody can change is
 * a fairness bucket anybody can leave.
 */
export function deviceIdFor(request: Request): string {
  const device = request.headers.get("X-Device-Id")?.trim();
  return device && /^[A-Za-z0-9-]{16,64}$/.test(device) ? device : "unknown";
}
