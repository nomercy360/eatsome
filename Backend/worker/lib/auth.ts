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

export async function requireAccount(
  authorizationHeader: string | undefined,
  env: Env,
): Promise<string> {
  const token = bearerToken(authorizationHeader);
  if (!token || !(await tokensMatch(token, env.EATSOME_API_TOKEN))) {
    throw new HttpError(401, "A valid bearer token is required.");
  }
  return env.ACCOUNT_ID;
}
