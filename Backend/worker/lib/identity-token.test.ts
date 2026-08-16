import { beforeEach, describe, expect, it, vi } from "vitest";
import { HttpError } from "./http-error";
import {
  parseAudiences,
  providerMetadata,
  resetJwksCache,
  verifyIdentityToken,
} from "./identity-token";

/**
 * The happy path is the least interesting test in this file.
 *
 * Every historical JWT disaster is a rejection that did not happen: the token
 * whose signature was never checked, the one signed `alg: none`, the one minted
 * for somebody else's app. So each of those gets a test that constructs the bad
 * token for real — same signer, same JWKS, one thing wrong — rather than
 * asserting on a hand-written string that might be malformed for an unrelated
 * reason and pass the test by accident.
 */

const APPLE_ISSUER = "https://appleid.apple.com";
const BUNDLE_ID = "app.shaman.tracker";

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function encodeJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

type Signer = {
  kid: string;
  jwks: { keys: (JsonWebKey & { kid: string })[] };
  sign(header: Record<string, unknown>, claims: Record<string, unknown>): Promise<string>;
};

async function makeSigner(kid: string): Promise<Signer> {
  // Cast because this file typechecks under both the Worker lib and Node's, and
  // only one of them narrows these two calls.
  const pair = (await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  return {
    kid,
    jwks: { keys: [{ ...jwk, kid, alg: "RS256", use: "sig" }] },
    async sign(header, claims) {
      const body = `${encodeJson({ kid, alg: "RS256", ...header })}.${encodeJson(claims)}`;
      const signature = await crypto.subtle.sign(
        "RSASSA-PKCS1-v1_5",
        pair.privateKey,
        new TextEncoder().encode(body),
      );
      return `${body}.${base64url(new Uint8Array(signature))}`;
    },
  };
}

const now = 1_800_000_000_000;

function appleClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    iss: APPLE_ISSUER,
    aud: BUNDLE_ID,
    sub: "001234.abcdef.0000",
    iat: Math.floor(now / 1000) - 30,
    exp: Math.floor(now / 1000) + 600,
    email: "someone@privaterelay.appleid.com",
    email_verified: "true",
    ...overrides,
  };
}

function jwksFetch(signer: Signer): { fetch: typeof fetch; calls: () => number } {
  let calls = 0;
  const impl = vi.fn(async (input: RequestInfo | URL) => {
    calls += 1;
    expect(String(input)).toBe(providerMetadata.apple.jwksUrl);
    return new Response(JSON.stringify(signer.jwks), {
      headers: { "content-type": "application/json" },
    });
  });
  return { fetch: impl as unknown as typeof fetch, calls: () => calls };
}

describe("identity token verification", () => {
  beforeEach(() => {
    resetJwksCache();
  });

  it("accepts a well-formed Apple token and returns only the subject", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims());
    const identity = await verifyIdentityToken("apple", token, {
      audiences: [BUNDLE_ID],
      now,
      fetch: jwksFetch(signer).fetch,
    });
    expect(identity.subject).toBe("001234.abcdef.0000");
    expect(identity.provider).toBe("apple");
    // Apple sends the string, not the boolean, and has for years.
    expect(identity.emailVerified).toBe(true);
  });

  it("rejects a token minted for another app", async () => {
    // The one that matters most and looks least broken: a real Apple token,
    // correctly signed, currently valid — for somebody else's bundle id.
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims({ aud: "com.someone.else" }));
    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/different app/);
  });

  it("refuses to verify at all when no audience is configured", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims());
    // An empty allowlist must not read as "accept anything".
    await expect(
      verifyIdentityToken("apple", token, { audiences: [], now, fetch: jwksFetch(signer).fetch }),
    ).rejects.toMatchObject({ status: 503 });
  });

  it("rejects an expired token, allowing only a minute of clock skew", async () => {
    const signer = await makeSigner("apple-key-1");
    const expired = await signer.sign({}, appleClaims({ exp: Math.floor(now / 1000) - 120 }));
    await expect(
      verifyIdentityToken("apple", expired, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/expired/);

    const justPast = await signer.sign({}, appleClaims({ exp: Math.floor(now / 1000) - 30 }));
    await expect(
      verifyIdentityToken("apple", justPast, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).resolves.toMatchObject({ subject: "001234.abcdef.0000" });
  });

  it("rejects a token whose payload was edited after signing", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims());
    const [header, , signature] = token.split(".") as [string, string, string];
    const swapped = `${header}.${encodeJson(appleClaims({ sub: "someone.elses.subject" }))}.${signature}`;
    await expect(
      verifyIdentityToken("apple", swapped, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/signature/);
  });

  it("rejects alg: none, signature or no signature", async () => {
    const signer = await makeSigner("apple-key-1");
    const header = encodeJson({ alg: "none", kid: signer.kid });
    const payload = encodeJson(appleClaims());
    await expect(
      verifyIdentityToken("apple", `${header}.${payload}.`, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/algorithm/);
  });

  it("rejects a token asking to be verified as an HMAC", async () => {
    // `alg: HS256` against an RSA public key is the classic key-confusion
    // attack: the public key is published, so it makes a fine shared secret.
    const signer = await makeSigner("apple-key-1");
    const header = encodeJson({ alg: "HS256", kid: signer.kid });
    const payload = encodeJson(appleClaims());
    await expect(
      verifyIdentityToken("apple", `${header}.${payload}.c2ln`, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/algorithm/);
  });

  it("rejects a token from a different issuer", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign(
      {},
      appleClaims({ iss: "https://appleid.apple.com.evil.test" }),
    );
    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/issuer/);
  });

  it("rejects a token signed by a key the provider does not publish", async () => {
    const attacker = await makeSigner("apple-key-1");
    const provider = await makeSigner("apple-key-1");
    const token = await attacker.sign({}, appleClaims());
    // Same kid, different key: the JWKS lookup succeeds and the signature does
    // not, which is the failure mode a kid-only check would miss.
    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(provider).fetch,
      }),
    ).rejects.toThrow(/signature/);
  });

  it("rejects an unknown key id rather than trying the keys it has", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({ kid: "apple-key-9" }, appleClaims());
    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/unknown key/);
  });

  it("rejects a token with no subject", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims({ sub: "  " }));
    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/subject/);
  });

  it("rejects a token whose nonce belongs to a different sign-in", async () => {
    const signer = await makeSigner("apple-key-1");
    // Apple echoes the hex SHA-256 of the client's raw nonce.
    const raw = "0123456789abcdef";
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
    const hashed = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    const token = await signer.sign({}, appleClaims({ nonce: hashed }));

    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        nonce: raw,
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).resolves.toMatchObject({ subject: "001234.abcdef.0000" });

    await expect(
      verifyIdentityToken("apple", token, {
        audiences: [BUNDLE_ID],
        nonce: "a-different-attempt",
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/this sign-in/);

    // A token with no nonce at all cannot satisfy a caller that asked for one.
    const bare = await signer.sign({}, appleClaims());
    await expect(
      verifyIdentityToken("apple", bare, {
        audiences: [BUNDLE_ID],
        nonce: raw,
        now,
        fetch: jwksFetch(signer).fetch,
      }),
    ).rejects.toThrow(/this sign-in/);
  });

  it("rejects garbage before it reaches a decoder", async () => {
    const signer = await makeSigner("apple-key-1");
    const options = { audiences: [BUNDLE_ID], now, fetch: jwksFetch(signer).fetch };
    for (const bad of ["", "not-a-token", "a.b", "a.b.c.d", "!!!.???.***"]) {
      await expect(verifyIdentityToken("apple", bad, options)).rejects.toBeInstanceOf(HttpError);
    }
  });

  it("fetches the key set once and reuses it", async () => {
    const signer = await makeSigner("apple-key-1");
    const jwks = jwksFetch(signer);
    const token = await signer.sign({}, appleClaims());
    await verifyIdentityToken("apple", token, { audiences: [BUNDLE_ID], now, fetch: jwks.fetch });
    await verifyIdentityToken("apple", token, { audiences: [BUNDLE_ID], now, fetch: jwks.fetch });
    expect(jwks.calls()).toBe(1);
  });

  it("says the provider is unreachable rather than that the user is wrong", async () => {
    const signer = await makeSigner("apple-key-1");
    const token = await signer.sign({}, appleClaims());
    const failing = (async () => {
      throw new Error("network");
    }) as unknown as typeof fetch;
    // A 401 here would tell someone their perfectly good sign-in was refused.
    await expect(
      verifyIdentityToken("apple", token, { audiences: [BUNDLE_ID], now, fetch: failing }),
    ).rejects.toMatchObject({ status: 503 });
  });

  it("matches Apple's issuer exactly, and only Apple's", () => {
    // Exact match, never a suffix or a `startsWith`: `https://appleid.apple.com`
    // and `https://appleid.apple.com.example.net` differ by a check somebody
    // could reasonably get wrong once.
    expect(providerMetadata.apple.issuers).toEqual(["https://appleid.apple.com"]);
    expect(Object.keys(providerMetadata)).toEqual(["apple"]);
  });

  it("reads a comma-separated audience list without turning blanks into wildcards", () => {
    expect(parseAudiences("a, b ,, c")).toEqual(["a", "b", "c"]);
    expect(parseAudiences("")).toEqual([]);
    expect(parseAudiences(undefined)).toEqual([]);
  });
});
