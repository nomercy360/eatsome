# eatsome backend

Cloudflare-native API for recognition, private model-input storage, append-only event sync, and
consent-controlled meal eval pairs.

## Stack

- Cloudflare Workers and Hono 4
- One private Cloudflare R2 bucket, split into `media/` and `corpus/` lifecycles
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
POST /api/v1/recognitions/:sha/rerun  rerun from the model input already in R2
POST /api/v1/events/batch  idempotently append up to 500 device events
GET  /api/v1/events        cursor-based event sync
GET  /api/v1/evals         inspect model-output → human-correction pairs
GET  /api/v1/media/:sha    authenticated private photo stream
POST /api/v1/corpus/items  attach a consented, privacy-filtered crop to a saved meal
DELETE /api/v1/corpus/consent  retroactively remove one device's corpus items
DELETE /api/v1/account     erase the device's media, corpus provenance, and D1 data
```

The recognition request contains `photoHash`, `mimeType`, `imageBase64`, optional `note`, and an
optional provider override. The Worker verifies the hash and stores the exact model-input bytes in
R2 before calling the provider. It passes the request bytes directly to the provider path; the
initial inference never reads them back from R2. A provider failure therefore still leaves a
repairable input for `/rerun`, and a cancelled confirmation sheet becomes an orphan eligible for
scheduled cleanup.

The cache identity is `(account, input fingerprint, prompt version, model)`. The input fingerprint
includes the normalized note: the same plate plus “fried in butter” is a different model question.
The model id keeps provider comparisons real. D1 contains metadata and provenance, never image
bytes.

Event ingestion stores the original append-only event unchanged. A meal event containing
`recognitionEvidence` is additionally projected into `meal_evals`, where initial and final items
are queryable side by side. Re-uploading the same event id is a successful no-op.

## Two image lifecycles

```text
recognition upload
  └─ media/{device}/{yyyy-mm}/{source-sha}.jpg   exact 1024px JPEG model input

confirmed meal + explicit consent + safe client crop
  └─ corpus/{crop-sha}.jpg                      separate privacy-filtered bytes
```

The crop has its own `corpusHash`; `sourcePhotoHash` remains the provenance link. The server never
copies a raw `media/` object into the corpus as a fallback. `facesExcluded` and
`otherMealsExcluded` must both be asserted by the crop producer, and the meal/photo pair must
already exist in the event projection.

Deleting a meal tombstones its media reference and removes the source object only when no other
meal uses the same hash. Opt-out removes every `corpus_items` row for `source_user` and deletes only
crop objects that have no remaining provenance references. Account deletion lists the
`media/{device}/` prefix, bulk-deletes it, applies the corpus cascade, then removes D1 rows.

The scheduled Worker removes unreferenced media older than 24 hours every Sunday. R2 already
defaults incomplete multipart uploads to a seven-day lifecycle; verify that rule in the bucket or
shorten it if uploads later move to multipart. The bucket must remain private—photo reads go
through the authenticated Worker route.

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
export CLOUDFLARE_API_TOKEN=…   # Workers Scripts: Edit, D1: Edit, R2: Edit, Account Settings: Read
./scripts/bootstrap-remote.sh
```

`wrangler login` works instead of the token if you would rather use the browser.
The first run creates the D1 database and private `eatsome-media` bucket, then prints the database
id. Paste that id into `wrangler.jsonc` and run it again; it sets the secrets, migrates, and
deploys. It is safe to re-run—existing resources and secrets are left alone.

The bearer token is deliberately a single-owner bootstrap mechanism. Replace it with Sign in with
Apple before inviting unrelated users; do not turn the shared token into a multi-user identity
system.

Every stored-data route also requires `X-Device-Id` (16–64 letters, numbers, or hyphens). The
header is a stable partition, not authentication. Add Sign in with Apple/App Attest before the API
is opened to unrelated users.
