import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { HttpError } from "./http-error";
import { mintTranscriptionKey } from "./soniox";

const env = { SONIOX_API_KEY: "soniox-secret" } as Env;

function transport(status: number, body: unknown) {
  const calls: { url?: string; init?: RequestInit } = {};
  const send = (async (url: unknown, init?: RequestInit) => {
    calls.url = String(url);
    calls.init = init;
    return new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
  return { calls, send };
}

describe("soniox temporary keys", () => {
  it("is a clean 503 naming the variable when the key is unset", async () => {
    // The same shape as an unconfigured recognition provider, and what the app
    // reads to disable the mic button.
    const error = await mintTranscriptionKey({ SONIOX_API_KEY: "" } as Env).catch((e) => e);
    expect(error).toBeInstanceOf(HttpError);
    expect(error.status).toBe(503);
    expect(error.message).toContain("SONIOX_API_KEY");
  });

  it("mints a single-use key scoped to one short dictation", async () => {
    const { calls, send } = transport(200, {
      api_key: "temp-key",
      expires_at: "2026-08-09T12:02:00Z",
    });
    const key = await mintTranscriptionKey(env, send);

    expect(key).toEqual({ apiKey: "temp-key", expiresAt: "2026-08-09T12:02:00Z" });
    expect(calls.url).toBe("https://api.soniox.com/v1/auth/temporary-api-key");
    const headers = calls.init?.headers as Record<string, string>;
    // The real key rides in the header to Soniox and appears nowhere in what
    // the caller receives.
    expect(headers.authorization).toBe("Bearer soniox-secret");
    const sent = JSON.parse(String(calls.init?.body));
    expect(sent.usage_type).toBe("transcribe_websocket");
    expect(sent.single_use).toBe(true);
    // A dictated meal is seconds; neither window is anywhere near an hour.
    expect(sent.expires_in_seconds).toBeLessThanOrEqual(300);
    expect(sent.max_session_duration_seconds).toBeLessThanOrEqual(600);
  });

  it("treats a Soniox failure as a bad gateway, not a missing key", async () => {
    const { send } = transport(401, { error: "bad key" });
    const error = await mintTranscriptionKey(env, send).catch((e) => e);
    expect(error).toBeInstanceOf(HttpError);
    expect(error.status).toBe(502);
  });

  it("refuses a 200 that carries no key", async () => {
    const { send } = transport(200, {});
    const error = await mintTranscriptionKey(env, send).catch((e) => e);
    expect(error).toBeInstanceOf(HttpError);
    expect(error.status).toBe(502);
  });
});
