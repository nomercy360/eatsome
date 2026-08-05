# eatsome backend

Cloudflare-native API for recognition, append-only event sync, and automatically collected meal
eval pairs.

## Stack

- Cloudflare Workers and Hono 4
- Cloudflare D1 through Drizzle ORM 0.45; Drizzle Kit owns migrations
- Zod 4 for request validation and the strict OpenAI JSON Schema
- Direct OpenAI Responses API using `gpt-5.6-luna`
- TypeScript 7, Vitest 4, Biome 2, Node 24, and pnpm 11

Versions intentionally match the working `kata` backend.

## Local setup

```bash
cd Backend
pnpm install
cp .dev.vars.example .dev.vars
pnpm db:migrate:local
pnpm dev
```

Replace both placeholder values in `.dev.vars`. The local file is ignored and must never be
committed.

## API

`GET /api/health` is public. Every `/api/v1/*` route requires
`Authorization: Bearer <EATSOME_API_TOKEN>`.

```text
POST /api/v1/recognitions  proxy one image to OpenAI or Gemini; cache by account/photo/prompt/model
POST /api/v1/events/batch  idempotently append up to 500 device events
GET  /api/v1/events        cursor-based event sync
GET  /api/v1/evals         inspect model-output → human-correction pairs
```

The recognition request contains `photoHash`, `mimeType`, `imageBase64`, and an optional
`provider` (`openai` or `gemini`) that overrides `RECOGNITION_PROVIDER` for that call, so a device
can run its own comparison through the proxy. Both providers get the same prompt and are parsed
into the same contract; the model id is part of the cache key, so asking the second provider about
a photo the first has already seen costs a real call instead of replaying an answer that came from
somewhere else. `GET /api/health` reports both, including which one is missing a key.

The worker recomputes the SHA-256 before using the cache. Photos pass through memory to the
provider and are never written to D1. D1 retains only the hash, parsed result, raw model JSON,
prompt and model provenance, and token and latency telemetry.

Event ingestion stores the original append-only event unchanged. A meal event containing
`recognitionEvidence` is additionally projected into `meal_evals`, where initial and final items
are queryable side by side. Re-uploading the same event id is a successful no-op.

## Useful commands

```bash
pnpm db:generate
pnpm db:migrate:local
pnpm typecheck
pnpm test
pnpm check
pnpm verify
```

## Deploying

Authenticate once, then one script does the rest:

```bash
export CLOUDFLARE_API_TOKEN=…   # Workers Scripts: Edit, D1: Edit, Account Settings: Read
./scripts/bootstrap-remote.sh
```

`wrangler login` works instead of the token if you would rather use the browser.
The first run creates the D1 database and prints its id; paste that into
`wrangler.jsonc` and run it again, and it will set the five secrets, migrate and
deploy. It is safe to re-run — secrets already present are left alone.

The bearer token is deliberately a single-owner bootstrap mechanism. Replace it with Sign in with
Apple before inviting unrelated users; do not turn the shared token into a multi-user identity
system.
