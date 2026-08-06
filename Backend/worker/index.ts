import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import {
  corpusItemRequestSchema,
  evalListQuerySchema,
  eventListQuerySchema,
  ingestEventsRequestSchema,
  recognitionRequestSchema,
  refinementRequestSchema,
  rerunRecognitionRequestSchema,
  sha256Schema,
} from "../src/contracts";
import { apiKeyFor, keyVariableFor, modelFor, resolveProvider } from "./ai/recognize";
import { addCorpusItem, deleteAccountData, deleteOrphanCorpus, optOutCorpus } from "./data/corpus";
import { ingestEvents, listEvents, listMealEvals } from "./data/events";
import { deleteOrphanMedia, getMediaObject } from "./data/media";
import { recognizeMeal, rerunRecognition } from "./data/recognitions";
import { refineMeal } from "./data/refinements";
import type { Env } from "./env";
import { requireAccount, requireStableAccount } from "./lib/auth";
import { HttpError } from "./lib/http-error";
import { enforceRecognitionLimits, enforceSyncLimits } from "./lib/limits";

type AppContext = {
  Bindings: Env;
  Variables: { accountId: string };
};

export const app = new Hono<AppContext>().basePath("/api");

app.use("*", async (c, next) => {
  if (c.req.path === "/api/health") return next();
  const accountId = await requireAccount(c.req.header("Authorization"), c.env, c.req.raw);
  c.set("accountId", accountId);
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
  await enforceRecognitionLimits(c.env, c.get("accountId"));
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
    await enforceRecognitionLimits(c.env, c.get("accountId"));
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
    await enforceRecognitionLimits(c.env, c.get("accountId"));
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

app.post("/v1/events/batch", zValidator("json", ingestEventsRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  const result = await ingestEvents(c.env, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.inserted === 0 ? 200 : 201);
});

app.get("/v1/media/:hash", async (c) => {
  const accountId = requireStableAccount(c.get("accountId"));
  const parsed = sha256Schema.safeParse(c.req.param("hash"));
  if (!parsed.success) throw new HttpError(400, "Invalid photo hash.");
  const object = await getMediaObject(c.env, accountId, parsed.data.toLowerCase());
  if (!object) throw new HttpError(404, "Photo not found.");
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "private, max-age=300");
  headers.set("content-security-policy", "default-src 'none'; sandbox");
  return new Response(object.body, { headers });
});

app.post("/v1/corpus/items", zValidator("json", corpusItemRequestSchema), async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  const result = await addCorpusItem(c.env, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.cached ? 200 : 201);
});

app.delete("/v1/corpus/consent", async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  return c.json(await optOutCorpus(c.env, c.get("accountId")));
});

app.delete("/v1/account", async (c) => {
  await enforceSyncLimits(c.env, c.get("accountId"));
  return c.json(await deleteAccountData(c.env, c.get("accountId")));
});

app.get("/v1/events", zValidator("query", eventListQuerySchema), async (c) => {
  const query = c.req.valid("query");
  return c.json(await listEvents(c.env.DB, c.get("accountId"), query.cursor, query.limit));
});

app.get("/v1/evals", zValidator("query", evalListQuerySchema), async (c) => {
  const query = c.req.valid("query");
  return c.json({ evals: await listMealEvals(c.env.DB, c.get("accountId"), query.limit) });
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
  fetch: app.fetch,
  scheduled(_controller, env, context) {
    context.waitUntil(
      Promise.all([deleteOrphanMedia(env), deleteOrphanCorpus(env)]).then(([media, corpus]) => {
        console.log(`orphan cleanup deleted ${media} media and ${corpus} corpus objects`);
      }),
    );
  },
} satisfies ExportedHandler<Env>;
