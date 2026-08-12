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

Replace the provider-key placeholders you need in `.dev.vars`. The local file is ignored and must
never be committed.

## API

`GET /api/health` is public. `POST /api/v1/auth/sessions` verifies a Sign in with
Apple identity token and returns an opaque 180-day eatsome session. Every other
production `/api/v1/*` route requires that session in
`Authorization: Bearer <session>`. Only its SHA-256 digest is stored in D1.
`X-Device-Id` names the legacy device partition that is permanently adopted on
first sign-in; it is not an authentication credential.

```text
POST /api/v1/auth/sessions  exchange a provider identity token for an eatsome account session
DELETE /api/v1/auth/sessions  revoke the current device's session
POST /api/v1/recognitions  read a meal from a photo, the person's words, or both; cache by account/input/prompt/model
POST /api/v1/recognitions/:sha/rerun  rerun from the model input already in R2
POST /api/v1/voice/key     mint a single-use, short-lived Soniox transcription key
POST /api/v1/recognitions/:sha/refine return a delta against the current list, using the R2 photo
POST /api/v1/refinements    the same delta with no photo, for a meal typed in or never read
POST /api/v1/events/batch  idempotently append up to 500 device events
GET  /api/v1/events        cursor-based event sync
GET  /api/v1/evals         inspect model-output → human-correction pairs
GET  /api/v1/media/:sha    authenticated private photo stream
POST /api/v1/corpus/items  attach a consented, privacy-filtered crop to a saved meal
DELETE /api/v1/corpus/consent  retroactively remove one device's corpus items
DELETE /api/v1/account     erase the device's media, corpus provenance, and D1 data
```

A recognition request is a photograph (`photoHash` + `mimeType` + `imageBase64`,
together or not at all), the person's words (`said`), or both; a request with
neither is a 400. `note` remains the photo-annotation field the refine and
rerun paths use — `said` is the meal being described, `note` is a photograph
being annotated, and the prompt frames them differently. The response's
`photoKey` is null for a described meal, and the cache fingerprint covers the
text, so two typed meals never replay each other's answer.

`POST /api/v1/voice/key` returns `{ "apiKey", "expiresAt" }` (camelCase, like
every response here): a single-use Soniox key, redeemable for 120 s, capped at
a 300 s session. The device opens the transcription websocket itself; no audio
passes through the Worker, and the real key never leaves it. Unset
`SONIOX_API_KEY` is a 503 naming the variable.

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

## Branded food

`RECOGNITION_SEARCH=on` hands the recognition call `googleSearch` as a tool. The
model reaches for it on a chain's product and ignores it on food nobody
published — an ordinary home meal performs no search and costs nothing extra —
and it answers in the same schema either way. A Subway JP American Clubhouse
footlong publishes 698 kcal: ungrounded this prompt answered 845 and 865,
grounded it answers 699.

The request's country goes into the turn with it, from `CF-IPCountry`, as the
weakest evidence in the prompt. Nobody types their own country, and without it
the same words returned 1216 kcal — correctly, for the American sandwich. It is
part of the cache fingerprint for the same reason.

What none of this buys is a citation: `generateContent` returns no grounding
metadata beside a response schema, so a grounded figure is `model`, and the app
calls it an estimate. A pipeline that fetched brands' own pages to earn one URL
lived in `worker/ai/published.ts` for a day; it resolved one chain in seven and
was deleted in favour of this.

Event ingestion stores the original append-only event unchanged. A meal event containing
`recognitionEvidence` is additionally projected into `meal_evals`, where initial and final items
are queryable side by side. Re-uploading the same event id is a successful no-op.

## Two image lifecycles

```text
recognition upload
  └─ media/{account}/{yyyy-mm}/{source-sha}.jpg  exact 2048px JPEG model input

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
`media/{account}/` prefix, bulk-deletes it, applies the corpus cascade, then removes D1 rows.

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
deploys. It is safe to re-run—existing resources and provider secrets are left alone. On the first
session-bearer deployment it removes the retired `EATSOME_API_TOKEN` secret after the new Worker is
live.

There is nothing per-person to provision and no backend secret in a TestFlight
archive. Apple proves the person's identity during sign-in; the Worker mints a
random 256-bit session and the app stores it in the Keychain. Requests after
sign-in use that session as their bearer credential. A second device signing in
with the same Apple account joins the account's partition union, so meal history
follows the person without rewriting legacy rows.

Sessions expire after 180 days and are revoked per device at sign-out. Provider
credentials remain Worker secrets and never reach the app.
