import type { identityProviders } from "../../src/contracts";
import { HttpError } from "./http-error";

/**
 * Reading the token a phone hands us, rather than believing it.
 *
 * Sign in with Apple and Google both end with the client holding a signed JWT
 * and posting it here. The only thing that makes that token worth more than the
 * `X-Device-Id` header it replaces is this file: signature against the
 * provider's published key, issuer, audience, expiry. Skip any one of them and
 * the `sub` we extract is a string the caller chose, which is strictly worse
 * than the device id — a device id is honest about being a partition, whereas a
 * `sub` is about to be treated as proof of who someone is and will be used to
 * hand them another account's meal history.
 *
 * Concretely, the three ways this is normally got wrong:
 *
 *   - Decoding the payload without verifying the signature. `atob` on the middle
 *     segment returns perfectly well-formed claims for a token nobody signed.
 *   - Honouring the `alg` header. `alg: none` is a token with an empty
 *     signature, and `alg: HS256` against an RSA public key turns a *published*
 *     value into the HMAC secret. The algorithm is therefore chosen here, from
 *     the key type, and the header's opinion is only ever checked for
 *     disagreement.
 *   - Not checking `aud`. Apple and Google will happily sign a token for any
 *     app; without the audience check, a token minted for someone else's app is
 *     accepted here and its `sub` names one of their users.
 *
 * Everything runs on WebCrypto. No `node:` import survives a Worker deploy.
 */

export type IdentityProvider = (typeof identityProviders)[number];

type ProviderMetadata = {
  /** Every spelling the provider is allowed to use in `iss`. Exact match only. */
  issuers: string[];
  jwksUrl: string;
};

/**
 * Both endpoints are documented, stable, and unauthenticated. Google publishes
 * two issuer spellings for the same tokens and always has; accepting both is
 * the documented behaviour rather than a loosening.
 */
export const providerMetadata: Record<IdentityProvider, ProviderMetadata> = {
  apple: {
    issuers: ["https://appleid.apple.com"],
    jwksUrl: "https://appleid.apple.com/auth/keys",
  },
  google: {
    issuers: ["https://accounts.google.com", "accounts.google.com"],
    jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
  },
};

export type VerifiedIdentity = {
  provider: IdentityProvider;
  /** The provider's stable, per-app user id. The only claim we store. */
  subject: string;
  email: string | null;
  emailVerified: boolean;
  expiresAt: number;
};

export type VerifyOptions = {
  /**
   * The bundle ids / client ids this deployment is willing to be. Empty is a
   * configuration error, never a wildcard: an empty allowlist that matched
   * everything would be indistinguishable from a correct one until somebody
   * signed in with a token from another app.
   */
  audiences: string[];
  /**
   * The raw nonce the client generated for this sign-in, if it sent one. See
   * `nonceMatches` — this binds a token to one sign-in attempt but is not a
   * server-issued challenge, so it is not full replay protection.
   */
  nonce?: string;
  now?: number;
  fetch?: typeof fetch;
};

/** Providers' clocks and ours disagree by seconds; a minute covers it. */
const CLOCK_SKEW_MS = 60_000;
/** Apple rotates roughly monthly and publishes the successor well in advance. */
const JWKS_TTL_MS = 6 * 3_600_000;
/**
 * An unknown `kid` is the signal that a key rotated early, so it forces a
 * refetch — which is also a free way for a caller to make us hammer Apple.
 * One refetch a minute per provider is the ceiling on that.
 */
const JWKS_REFETCH_FLOOR_MS = 60_000;

/** Cloudflare's `JsonWebKey` omits `kid`, which is the field the lookup is on. */
type SigningJwk = JsonWebKey & { kid?: string; kty?: string };

type CachedJwks = { keys: SigningJwk[]; fetchedAt: number };

/**
 * Module scope, so it lives as long as the isolate and no longer. Workers
 * recycle isolates constantly, so this is a hit-rate improvement rather than a
 * cache with a coherency problem: the worst case is a fetch we already budget
 * for, and a rotated-away key is caught by the signature check regardless.
 */
const jwksCache = new Map<string, CachedJwks>();

/** Tests only. Production never wants a cold cache mid-flight. */
export function resetJwksCache(): void {
  jwksCache.clear();
}

function decodeSegment(segment: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(segment)) throw new HttpError(401, "Malformed identity token.");
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function decodeJson(segment: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(decodeSegment(segment)));
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("not an object");
    }
    return value as Record<string, unknown>;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(401, "Malformed identity token.");
  }
}

async function loadJwks(
  url: string,
  fetchImpl: typeof fetch,
  now: number,
): Promise<CachedJwks | null> {
  let response: Response;
  try {
    response = await fetchImpl(url, { headers: { accept: "application/json" } });
  } catch {
    return null;
  }
  if (!response.ok) return null;
  const body = (await response.json().catch(() => null)) as { keys?: SigningJwk[] } | null;
  if (!body || !Array.isArray(body.keys)) return null;
  const cached: CachedJwks = { keys: body.keys, fetchedAt: now };
  jwksCache.set(url, cached);
  return cached;
}

async function signingKey(
  url: string,
  kid: string,
  fetchImpl: typeof fetch,
  now: number,
): Promise<CryptoKey> {
  let cached = jwksCache.get(url);
  if (!cached || now - cached.fetchedAt > JWKS_TTL_MS) {
    cached = (await loadJwks(url, fetchImpl, now)) ?? cached;
  }
  let jwk = cached?.keys.find((key) => key.kid === kid);
  if (!jwk && cached && now - cached.fetchedAt > JWKS_REFETCH_FLOOR_MS) {
    const refreshed = await loadJwks(url, fetchImpl, now);
    jwk = refreshed?.keys.find((key) => key.kid === kid);
  }
  if (!jwk) {
    // Not 401. The token may be perfectly good and the provider's key list
    // unreachable, and telling a user their sign-in was rejected because our
    // outbound fetch failed is a lie they cannot act on.
    if (!cached) throw new HttpError(503, "Could not reach the sign-in provider.");
    throw new HttpError(401, "Identity token was signed by an unknown key.");
  }
  // RS256 only, and it comes from the key material rather than the token. Apple
  // and Google both publish `RSA`/`RS256` keys; the day either adds an EC key,
  // this fails loudly instead of guessing an algorithm from attacker input.
  if (jwk.kty !== "RSA") {
    throw new HttpError(401, "Unsupported identity token key type.");
  }
  try {
    return await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    throw new HttpError(401, "Unusable identity token key.");
  }
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * Apple and Google echo a nonce differently, and both are correct.
 *
 * The convention on Apple is that the client hashes its raw nonce before
 * handing it to `ASAuthorizationAppleIDRequest`, so the token carries the
 * hex SHA-256 and the raw value never leaves the phone until it reaches us.
 * Google's native flows echo the string verbatim. Accepting either keeps one
 * client-side nonce implementation for both.
 *
 * What this is worth: it binds the token to a sign-in this client started, so a
 * token captured somewhere else cannot be posted here. What it is not: freshness.
 * The nonce is chosen by the client, not issued by us, so a client that replays
 * its *own* nonce and token replays successfully within the token's lifetime.
 * Making that impossible needs a server-minted challenge with a one-shot store,
 * which is a round trip and a table this milestone does not have. The damage is
 * bounded to the account the token already proves.
 */
async function nonceMatches(claim: string, raw: string): Promise<boolean> {
  return claim === raw || claim === (await sha256Hex(raw));
}

export async function verifyIdentityToken(
  provider: IdentityProvider,
  token: string,
  options: VerifyOptions,
): Promise<VerifiedIdentity> {
  if (options.audiences.length === 0) {
    throw new HttpError(503, `Sign in with ${provider} is not configured on this deployment.`);
  }
  const now = options.now ?? Date.now();
  const fetchImpl = options.fetch ?? fetch;
  const metadata = providerMetadata[provider];

  const segments = token.split(".");
  if (segments.length !== 3) throw new HttpError(401, "Malformed identity token.");
  const [headerSegment, payloadSegment, signatureSegment] = segments as [string, string, string];

  const header = decodeJson(headerSegment);
  // The header does not select the algorithm — the key does. This check exists
  // only to reject a token that is asking for something we are not about to do,
  // `none` and `HS256` included, before spending a fetch on it.
  if (header.alg !== "RS256") throw new HttpError(401, "Unsupported identity token algorithm.");
  const kid = typeof header.kid === "string" ? header.kid : null;
  if (!kid) throw new HttpError(401, "Identity token names no signing key.");

  const key = await signingKey(metadata.jwksUrl, kid, fetchImpl, now);
  const signature = decodeSegment(signatureSegment);
  const signed = new TextEncoder().encode(`${headerSegment}.${payloadSegment}`);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signature as BufferSource,
    signed as BufferSource,
  );
  if (!valid) throw new HttpError(401, "Identity token signature did not verify.");

  // Claims are only read after the signature holds. Reading them first is how a
  // forged token gets logged, counted, or cached as if it were a real user.
  const claims = decodeJson(payloadSegment);

  const issuer = typeof claims.iss === "string" ? claims.iss : "";
  if (!metadata.issuers.includes(issuer)) {
    throw new HttpError(401, "Identity token came from the wrong issuer.");
  }

  // `aud` is a string or an array of them, per RFC 7519.
  const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audience.some((value) => typeof value === "string" && options.audiences.includes(value))) {
    throw new HttpError(401, "Identity token was issued for a different app.");
  }

  const expiry = typeof claims.exp === "number" ? claims.exp * 1000 : 0;
  if (!expiry || expiry + CLOCK_SKEW_MS < now) {
    throw new HttpError(401, "Identity token has expired.");
  }
  const issuedAt = typeof claims.iat === "number" ? claims.iat * 1000 : null;
  if (issuedAt !== null && issuedAt - CLOCK_SKEW_MS > now) {
    throw new HttpError(401, "Identity token is not valid yet.");
  }

  if (options.nonce !== undefined) {
    const claimed = typeof claims.nonce === "string" ? claims.nonce : "";
    if (!claimed || !(await nonceMatches(claimed, options.nonce))) {
      throw new HttpError(401, "Identity token does not match this sign-in attempt.");
    }
  }

  const subject = typeof claims.sub === "string" ? claims.sub.trim() : "";
  if (!subject) throw new HttpError(401, "Identity token names no subject.");

  // Apple sends `email_verified` as the string "true" about as often as the
  // boolean, and only on the first authorization. It is recorded for support,
  // never for identification: the `sub` is the identity, an email is a label
  // that can move between accounts.
  const emailVerified = claims.email_verified === true || claims.email_verified === "true";
  const email = typeof claims.email === "string" && claims.email ? claims.email : null;

  return { provider, subject, email, emailVerified, expiresAt: expiry };
}

/** `APPLE_CLIENT_IDS`-style config: comma separated, whitespace tolerated. */
export function parseAudiences(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}
