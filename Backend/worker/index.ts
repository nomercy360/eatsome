import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import {
  eventPullQuerySchema,
  ingestEventsRequestSchema,
  recognitionRequestSchema,
  refinementRequestSchema,
  sha256Schema,
  signInRequestSchema,
} from "../src/contracts";
import { MEAL_PROMPT_VERSION } from "./ai/prompt";
import {
  deleteAccountData,
  deleteExpiredSessions,
  requireAuthenticatedPrincipal,
  revokeSession,
  signIn,
} from "./data/accounts";
import { ingestEvents, pullEvents } from "./data/events";
import { deleteOrphanMedia, getMediaObject } from "./data/media";
import { callerMarket, recognizeMeal } from "./data/recognitions";
import { refineMeal, refineMealFromNote } from "./data/refinements";
import type { Env } from "./env";
import { HttpError } from "./lib/http-error";
import { enforceRecognitionLimits, enforceSyncLimits } from "./lib/limits";
import { privacyPage } from "./privacy";

type AppContext = {
  Bindings: Env;
  Variables: {
    /** The account every row this request touches is written under and read
     *  from. There is no second partition and no union: see `data/accounts.ts`. */
    accountId: string;
    /** Which phone is asking. A label, never a credential. */
    deviceId: string;
  };
};

export const app = new Hono<AppContext>().basePath("/api");

app.use("*", async (c, next) => {
  if (c.req.path === "/api/health") return next();
  // The identity exchange proves itself with the provider-signed token in its
  // body. It cannot already require the eatsome session it is creating.
  if (c.req.method === "POST" && c.req.path === "/api/v1/auth/sessions") return next();
  const principal = await requireAuthenticatedPrincipal(c.env, c.req.raw);
  c.set("accountId", principal.accountId);
  c.set("deviceId", principal.deviceId);
  return next();
});

app.get("/health", async (c) => {
  const database = await c.env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
  return c.json({
    ok: database?.ok === 1,
    database: { configured: true },
    storage: { configured: true, private: true },
    recognition: {
      provider: "gemini",
      model: c.env.GEMINI_RECOGNITION_MODEL,
      promptVersion: MEAL_PROMPT_VERSION,
      search: c.env.RECOGNITION_SEARCH === "on",
      configured: Boolean(c.env.GEMINI_API_KEY),
    },
  });
});

app.post("/v1/recognitions", zValidator("json", recognitionRequestSchema), async (c) => {
  const accountId = c.get("accountId");
  await enforceRecognitionLimits(c.env, accountId);
  if (!c.env.GEMINI_API_KEY) {
    throw new HttpError(503, "Recognition is not configured. Add GEMINI_API_KEY to .dev.vars.");
  }
  const result = await recognizeMeal(
    c.env,
    accountId,
    c.req.valid("json"),
    callerMarket(c.req.raw),
  );
  c.header("Cache-Control", "no-store");
  return c.json(result, result.cached ? 200 : 201);
});

app.post(
  "/v1/recognitions/:hash/refine",
  zValidator("json", refinementRequestSchema),
  async (c) => {
    const accountId = c.get("accountId");
    await enforceRecognitionLimits(c.env, accountId);
    const photoHash = sha256Schema.safeParse(c.req.param("hash"));
    if (!photoHash.success) throw new HttpError(400, "Invalid photo hash.");
    const result = await refineMeal(
      c.env,
      accountId,
      photoHash.data.toLowerCase(),
      c.req.valid("json"),
    );
    c.header("Cache-Control", "no-store");
    return c.json(result, 201);
  },
);

// The same correction for a meal with no photograph — typed in by hand, or one
// whose reading failed. Not keyed on a hash because there is nothing to key on.
app.post("/v1/refinements", zValidator("json", refinementRequestSchema), async (c) => {
  const accountId = c.get("accountId");
  await enforceRecognitionLimits(c.env, accountId);
  const result = await refineMealFromNote(c.env, accountId, c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(result, 201);
});

/**
 * Trade Apple's identity token for a session.
 *
 * Verifying the token is the whole security boundary: signature against the
 * provider's published key, `iss`, `aud`, `exp` — see `lib/identity-token.ts`.
 * Calling it twice is free; only the session row is new each time, which is
 * what lets a client retry a failed sign-in.
 *
 * Rate limited as a sync operation. The token is verified, but the route
 * necessarily has no eatsome session yet and performs an outbound key fetch, so
 * it should not be free to hammer. It is keyed on the device id rather than an
 * account because there is no account until it succeeds — the one place in the
 * API where the header does any work.
 */
app.post("/v1/auth/sessions", zValidator("json", signInRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw.headers.get("X-Device-Id") ?? "anonymous");
  const result = await signIn(c.env, c.req.raw, c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(result, 201);
});

/** Sign out this device only; other devices keep their sessions. */
app.delete("/v1/auth/sessions", async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  c.header("Cache-Control", "no-store");
  return c.json(await revokeSession(c.env, c.req.raw));
});

// Sync is two-way and merges by id. Push is idempotent because an event is
// immutable; pull hands back the account's rows, including those another phone
// uploaded. Neither direction deletes anything — a deletion is a `meal_deleted`
// event like any other.
app.post("/v1/events/batch", zValidator("json", ingestEventsRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  const result = await ingestEvents(c.env, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.inserted === 0 ? 200 : 201);
});

// Each event comes back as the JSON *text* of its envelope, so the phone can
// append it to its log without parsing it. See `pullEvents`.
app.get("/v1/events", zValidator("query", eventPullQuerySchema), async (c) => {
  const page = await pullEvents(c.env.DB, c.get("accountId"), c.req.valid("query"));
  c.header("Cache-Control", "no-store");
  return c.json(page);
});

app.get("/v1/media/:hash", async (c) => {
  const parsed = sha256Schema.safeParse(c.req.param("hash"));
  if (!parsed.success) throw new HttpError(400, "Invalid photo hash.");
  const object = await getMediaObject(c.env, c.get("accountId"), parsed.data.toLowerCase());
  if (!object) throw new HttpError(404, "Photo not found.");
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "private, max-age=300");
  headers.set("content-security-policy", "default-src 'none'; sandbox");
  return new Response(object.body, { headers });
});

app.delete("/v1/account", async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  return c.json(await deleteAccountData(c.env, c.get("accountId")));
});

app.notFound((c) => c.json({ error: "API route not found." }, 404));

app.onError((error) => {
  if (!(error instanceof HttpError)) console.error(error);
  const status = error instanceof HttpError ? error.status : 500;
  const message = error instanceof Error ? error.message : "Unexpected server error.";
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "content-type": "application/json; charset=UTF-8" },
  });
});

export default {
  // The policy is checked before the API, and before the auth middleware: it is
  // a published document, and a published document behind a bearer token is not
  // published. Everything else falls through to the `/api` router as before.
  fetch(request, env, context) {
    return privacyPage(request) ?? app.fetch(request, env, context);
  },
  scheduled(_controller, env, context) {
    context.waitUntil(
      Promise.all([deleteOrphanMedia(env), deleteExpiredSessions(env)]).then(
        ([media, sessions]) => {
          console.log(
            `orphan cleanup deleted ${media} media objects and ${sessions} expired sessions`,
          );
        },
      ),
    );
  },
} satisfies ExportedHandler<Env>;
