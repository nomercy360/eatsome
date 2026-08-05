import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import {
  evalListQuerySchema,
  eventListQuerySchema,
  ingestEventsRequestSchema,
  recognitionRequestSchema,
} from "../src/contracts";
import { apiKeyFor, keyVariableFor, modelFor, resolveProvider } from "./ai/recognize";
import { ingestEvents, listEvents, listMealEvals } from "./data/events";
import { recognizeMeal } from "./data/recognitions";
import type { Env } from "./env";
import { requireAccount } from "./lib/auth";
import { HttpError } from "./lib/http-error";

type AppContext = {
  Bindings: Env;
  Variables: { accountId: string };
};

const app = new Hono<AppContext>().basePath("/api");

app.use("*", async (c, next) => {
  if (c.req.path === "/api/health") return next();
  const accountId = await requireAccount(c.req.header("Authorization"), c.env);
  c.set("accountId", accountId);
  return next();
});

app.get("/health", async (c) => {
  const database = await c.env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
  const active = resolveProvider(c.env);
  return c.json({
    ok: database?.ok === 1,
    database: { configured: true },
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

app.post("/v1/events/batch", zValidator("json", ingestEventsRequestSchema), async (c) => {
  const result = await ingestEvents(c.env.DB, c.get("accountId"), c.req.valid("json"));
  return c.json(result, result.inserted === 0 ? 200 : 201);
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

export default app;
