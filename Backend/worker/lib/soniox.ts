import type { Env } from "../env";
import { HttpError } from "./http-error";

const ENDPOINT = "https://api.soniox.com/v1/auth/temporary-api-key";

/**
 * How long the minted key stays redeemable. The app asks for it when the mic
 * button is tapped and opens the websocket immediately, so this covers a slow
 * network and nothing else — an unredeemed key should die young.
 */
const KEY_TTL_SECONDS = 120;

/** A dictated meal is seconds. Five minutes is the ceiling, not the norm. */
const MAX_SESSION_SECONDS = 300;

export type TranscriptionKey = {
  apiKey: string;
  /** ISO 8601, from Soniox. */
  expiresAt: string;
};

/**
 * The Worker's whole part in voice input: mint a single-use, short-lived key
 * and hand it over. The device opens the transcription websocket itself — no
 * audio flows through here, so a slow dictation costs this Worker nothing.
 */
export async function mintTranscriptionKey(
  env: Env,
  transport: typeof fetch = fetch,
): Promise<TranscriptionKey> {
  if (!env.SONIOX_API_KEY) {
    // The same shape as an unconfigured recognition provider: name the missing
    // variable so the fix is in the message. The app disables the mic on this.
    throw new HttpError(503, "Voice is not configured. Add SONIOX_API_KEY to .dev.vars.");
  }
  const response = await transport(ENDPOINT, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.SONIOX_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      usage_type: "transcribe_websocket",
      expires_in_seconds: KEY_TTL_SECONDS,
      single_use: true,
      max_session_duration_seconds: MAX_SESSION_SECONDS,
    }),
  });
  const body = (await response.json().catch(() => null)) as {
    api_key?: string;
    expires_at?: string;
  } | null;
  if (!response.ok || !body?.api_key || !body.expires_at) {
    throw new HttpError(502, `Soniox did not issue a temporary key (${response.status}).`);
  }
  return { apiKey: body.api_key, expiresAt: body.expires_at };
}
