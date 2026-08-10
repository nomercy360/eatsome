import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import {
  corpusItemRequestSchema,
  createPostRequestSchema,
  createTableRequestSchema,
  evalListQuerySchema,
  eventListQuerySchema,
  ingestEventsRequestSchema,
  joinTableRequestSchema,
  markReadRequestSchema,
  reactionRequestSchema,
  recognitionRequestSchema,
  refinementRequestSchema,
  rerunRecognitionRequestSchema,
  sha256Schema,
  signInRequestSchema,
  tableFeedQuerySchema,
  tablesListQuerySchema,
} from "../src/contracts";
import { apiKeyFor, keyVariableFor, modelFor, resolveProvider } from "./ai/recognize";
import { deleteExpiredSessions, resolvePrincipal, revokeSession, signIn } from "./data/accounts";
import { addCorpusItem, deleteAccountData, deleteOrphanCorpus, optOutCorpus } from "./data/corpus";
import { ingestEvents, listEvents, listMealEvals } from "./data/events";
import { deleteOrphanMedia, getMediaObject } from "./data/media";
import { recognizeMeal, rerunRecognition } from "./data/recognitions";
import { refineMeal, refineMealFromNote } from "./data/refinements";
import {
  createPost,
  createTable,
  deletePost,
  deleteTable,
  getFeed,
  getPostPhoto,
  joinTable,
  leaveTable,
  listTables,
  markRead,
  rotateInvite,
  setReaction,
} from "./data/tables";
import type { Env } from "./env";
import { requireAppToken, requireStableAccount } from "./lib/auth";
import { HttpError } from "./lib/http-error";
import { enforceRecognitionLimits, enforceSyncLimits } from "./lib/limits";
import { mintTranscriptionKey } from "./lib/soniox";
import { privacyPage } from "./privacy";

type AppContext = {
  Bindings: Env;
  Variables: {
    /** The partition new rows are written under. */
    accountId: string;
    /** Every partition this caller may read; contains `accountId`. */
    partitions: string[];
  };
};

export const app = new Hono<AppContext>().basePath("/api");

app.use("*", async (c, next) => {
  if (c.req.path === "/api/health") return next();
  await requireAppToken(c.req.header("Authorization"), c.env);
  const principal = await resolvePrincipal(c.env, c.req.raw);
  c.set("accountId", principal.accountId);
  c.set("partitions", principal.partitions);
  return next();
});

app.get("/health", async (c) => {
  const database = await c.env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
  const active = resolveProvider(c.env);
  return c.json({
    ok: database?.ok === 1,
    database: { configured: true },
    storage: { configured: true, private: true },
    recognition: {
      provider: active,
      model: modelFor(c.env, active),
      promptVersion: c.env.MEAL_PROMPT_VERSION,
      configured: Boolean(apiKeyFor(c.env, active)),
      // Both, so you can see which half of a comparison is missing a key
      // before a request fails rather than after.
      providers: {
        openai: {
          model: c.env.OPENAI_RECOGNITION_MODEL,
          configured: Boolean(c.env.OPENAI_API_KEY),
        },
        gemini: {
          model: c.env.GEMINI_RECOGNITION_MODEL,
          configured: Boolean(c.env.GEMINI_API_KEY),
        },
        anthropic: {
          model: c.env.ANTHROPIC_RECOGNITION_MODEL,
          configured: Boolean(c.env.ANTHROPIC_API_KEY),
        },
        qwen: {
          model: c.env.QWEN_RECOGNITION_MODEL,
          configured: Boolean(c.env.QWEN_API_KEY),
        },
      },
    },
  });
});

app.post("/v1/recognitions", zValidator("json", recognitionRequestSchema), async (c) => {
  await enforceRecognitionLimits(c.env, c.req.raw);
  const input = c.req.valid("json");
  const provider = resolveProvider(c.env, input.provider);
  if (!apiKeyFor(c.env, provider)) {
    throw new HttpError(
      503,
      `${provider} is not configured. Add ${keyVariableFor[provider]} to .dev.vars.`,
    );
  }
  const result = await recognizeMeal(c.env, c.get("accountId"), input);
  c.header("Cache-Control", "no-store");
  return c.json(result, result.cached ? 200 : 201);
});

app.post(
  "/v1/recognitions/:hash/rerun",
  zValidator("json", rerunRecognitionRequestSchema),
  async (c) => {
    await enforceRecognitionLimits(c.env, c.req.raw);
    const accountId = requireStableAccount(c.get("accountId"));
    const photoHash = sha256Schema.safeParse(c.req.param("hash"));
    if (!photoHash.success) throw new HttpError(400, "Invalid photo hash.");
    const input = c.req.valid("json");
    const provider = resolveProvider(c.env, input.provider);
    if (!apiKeyFor(c.env, provider)) {
      throw new HttpError(
        503,
        `${provider} is not configured. Add ${keyVariableFor[provider]} to .dev.vars.`,
      );
    }
    const result = await rerunRecognition(c.env, accountId, photoHash.data.toLowerCase(), input);
    c.header("Cache-Control", "no-store");
    return c.json(result, result.cached ? 200 : 201);
  },
);

app.post(
  "/v1/recognitions/:hash/refine",
  zValidator("json", refinementRequestSchema),
  async (c) => {
    await enforceRecognitionLimits(c.env, c.req.raw);
    const accountId = requireStableAccount(c.get("accountId"));
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
  await enforceRecognitionLimits(c.env, c.req.raw);
  const accountId = requireStableAccount(c.get("accountId"));
  const result = await refineMealFromNote(c.env, accountId, c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(result, 201);
});

// A dictation is about to become a recognition, so it shares the recognition
// rate limit. The key returned is single-use and dies in minutes; the real
// Soniox key never leaves the server, and no audio passes through it either —
// the device opens the transcription websocket itself.
app.post("/v1/voice/key", async (c) => {
  await enforceRecognitionLimits(c.env, c.req.raw);
  const key = await mintTranscriptionKey(c.env);
  c.header("Cache-Control", "no-store");
  return c.json(key, 201);
});

/**
 * Trade a provider's identity token for a session, and hand this device's
 * anonymous history to the account behind it.
 *
 * The contract, stated plainly because one half of it cannot be taken back:
 *
 *   - Verifying the token is the whole security boundary. Signature against the
 *     provider's published key, `iss`, `aud`, `exp` — see `lib/identity-token.ts`.
 *   - Adopting this device's partition is **permanent**. There is no unlink, and
 *     from then on that phone's pre-sign-in meals are readable by every device
 *     on the account. `merge.adopted` says whether it happened; `merge.conflict`
 *     says the partition already belonged to someone else, in which case nothing
 *     moved and the old history stays where it was.
 *   - Calling this twice is free. The account lookup, the link and the union are
 *     all idempotent; only the session row is new each time, which is what lets
 *     a client retry a failed sign-in without inventing a reconciliation.
 *
 * Rate limited as a sync operation. It is cheap, but it is unauthenticated
 * beyond the shared app token and it does a signature verification and an
 * outbound fetch, so it should not be free to hammer.
 */
app.post("/v1/auth/sessions", zValidator("json", signInRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const result = await signIn(c.env, c.req.raw, c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(result, 201);
});

/** Sign out this device only. Deliberately not an un-merge: the partition link
 *  survives, because a person signing out on one phone has not asked for their
 *  history to leave the account. */
app.delete("/v1/auth/sessions", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  c.header("Cache-Control", "no-store");
  return c.json(await revokeSession(c.env, c.req.raw));
});

app.post("/v1/events/batch", zValidator("json", ingestEventsRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const result = await ingestEvents(c.env, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.inserted === 0 ? 200 : 201);
});

app.get("/v1/media/:hash", async (c) => {
  const accountId = c.get("accountId");
  const parsed = sha256Schema.safeParse(c.req.param("hash"));
  if (!parsed.success) throw new HttpError(400, "Invalid photo hash.");
  requireStableAccount(accountId);
  const object = await getMediaObject(c.env, c.get("partitions"), parsed.data.toLowerCase());
  if (!object) throw new HttpError(404, "Photo not found.");
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "private, max-age=300");
  headers.set("content-security-policy", "default-src 'none'; sandbox");
  return new Response(object.body, { headers });
});

app.post("/v1/corpus/items", zValidator("json", corpusItemRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const result = await addCorpusItem(c.env, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.cached ? 200 : 201);
});

app.delete("/v1/corpus/consent", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await optOutCorpus(c.env, c.get("accountId")));
});

app.delete("/v1/account", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await deleteAccountData(c.env, c.get("partitions")));
});

app.get("/v1/events", zValidator("query", eventListQuerySchema), async (c) => {
  const query = c.req.valid("query");
  return c.json(await listEvents(c.env.DB, c.get("partitions"), query.cursor, query.limit));
});

app.get("/v1/evals", zValidator("query", evalListQuerySchema), async (c) => {
  const query = c.req.valid("query");
  return c.json({ evals: await listMealEvals(c.env.DB, c.get("accountId"), query.limit) });
});

// --- Tables: a small group feed of shared meals. ---------------------------
//
// Every route reads and writes through `data/tables.ts`; the design decisions
// live there and in `src/contracts.ts`. Membership is checked over the same
// partition union event reads use, and nothing here ever returns a partition
// string to another member. Sync-rate-limited: this is chat-shaped traffic,
// not model-shaped.

function tableCaller(c: { get(key: "accountId"): string; get(key: "partitions"): string[] }) {
  requireStableAccount(c.get("accountId"));
  return { accountId: c.get("accountId"), partitions: c.get("partitions") };
}

app.post("/v1/tables", zValidator("json", createTableRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const table = await createTable(c.env, tableCaller(c), c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(table, 201);
});

app.post("/v1/tables/join", zValidator("json", joinTableRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const table = await joinTable(c.env, tableCaller(c), c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(table);
});

app.get("/v1/tables", zValidator("query", tablesListQuerySchema), async (c) => {
  const query = c.req.valid("query");
  c.header("Cache-Control", "no-store");
  return c.json(await listTables(c.env, tableCaller(c), query.since));
});

app.get("/v1/tables/:id/feed", zValidator("query", tableFeedQuerySchema), async (c) => {
  const query = c.req.valid("query");
  c.header("Cache-Control", "no-store");
  return c.json(await getFeed(c.env, tableCaller(c), c.req.param("id"), query));
});

app.post("/v1/tables/:id/posts", zValidator("json", createPostRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  const post = await createPost(c.env, tableCaller(c), c.req.param("id"), c.req.valid("json"));
  c.header("Cache-Control", "no-store");
  return c.json(post, 201);
});

app.delete("/v1/tables/:id/posts/:postId", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await deletePost(c.env, tableCaller(c), c.req.param("id"), c.req.param("postId")));
});

app.put("/v1/tables/:id/reactions", zValidator("json", reactionRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await setReaction(c.env, tableCaller(c), c.req.param("id"), c.req.valid("json")));
});

app.put("/v1/tables/:id/read", zValidator("json", markReadRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await markRead(c.env, tableCaller(c), c.req.param("id"), c.req.valid("json").seq));
});

app.post("/v1/tables/:id/invite", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  c.header("Cache-Control", "no-store");
  return c.json(await rotateInvite(c.env, tableCaller(c), c.req.param("id")));
});

app.post("/v1/tables/:id/leave", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await leaveTable(c.env, tableCaller(c), c.req.param("id")));
});

app.delete("/v1/tables/:id", async (c) => {
  await enforceSyncLimits(c.env, c.req.raw);
  return c.json(await deleteTable(c.env, tableCaller(c), c.req.param("id")));
});

// The shared photo. Same headers as the private media route; the difference is
// the check — table membership, not object ownership — and the bucket prefix,
// which is the table's own. The sharer's `media/<account>/` object is never
// served to anyone but the sharer.
app.get("/v1/tables/:id/media/:postId", async (c) => {
  const object = await getPostPhoto(
    c.env,
    tableCaller(c),
    c.req.param("id"),
    c.req.param("postId"),
  );
  if (!object) throw new HttpError(404, "Photo not found.");
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "private, max-age=300");
  headers.set("content-security-policy", "default-src 'none'; sandbox");
  return new Response(object.body, { headers });
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
      Promise.all([
        deleteOrphanMedia(env),
        deleteOrphanCorpus(env),
        deleteExpiredSessions(env),
      ]).then(([media, corpus, sessions]) => {
        console.log(
          `orphan cleanup deleted ${media} media, ${corpus} corpus objects and ${sessions} expired sessions`,
        );
      }),
    );
  },
} satisfies ExportedHandler<Env>;
