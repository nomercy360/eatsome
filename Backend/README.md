# eatsome backend

Cloudflare-native API for one thing: reading a meal, keeping the photograph it was read from, and
mirroring the phone's append-only log so a second device sees the same history.

## Stack

- Cloudflare Workers and Hono 4
- One private Cloudflare R2 bucket, holding `media/` and nothing else
- Cloudflare D1 through Drizzle ORM 0.45; Drizzle Kit owns migrations
- Zod 4 for request validation and for the schema the Gemini contract is checked against
- Google's Gemini API (`generateContent`, `responseSchema`, `googleSearch` as a tool)
- TypeScript 7, Vitest 4, Biome 2, Node 24, and pnpm 11

## Local setup

```bash
cd Backend
pnpm install
cp .dev.vars.example .dev.vars   # then paste a Gemini API key
pnpm db:migrate:local
pnpm dev
```

The local `.dev.vars` is ignored and must never be committed.

## API

`GET /api/health` is public. `POST /api/v1/auth/sessions` verifies a Sign in with Apple identity
token and returns an opaque 180-day eatsome session. Every other `/api/v1/*` route requires that
session in `Authorization: Bearer <session>`, and only its SHA-256 digest is stored in D1.
`X-Device-Id` is a label — it names the phone on its session row and on the events it uploaded, so
one device can be signed out on its own. It authorizes nothing and keys no quota.

```text
POST   /api/v1/auth/sessions            exchange an Apple identity token for an account session
DELETE /api/v1/auth/sessions            revoke this device's session
POST   /api/v1/recognitions             read a meal from a photo, the person's words, or both
POST   /api/v1/recognitions/:sha/refine correct a meal in words, against the stored photograph
POST   /api/v1/refinements              the same correction with no photo
POST   /api/v1/events/batch             append up to 500 events, idempotent by event id
GET    /api/v1/events                   pull this account's log, oldest first, paged
GET    /api/v1/media/:sha               authenticated private photo stream
DELETE /api/v1/account                  erase every photograph, event and identity of this account
```

### Recognition

A request is a photograph (`photoHash` + `mimeType` + `imageBase64`, together or not at all), the
person's words (`said`), or both; a request with neither is a 400. `note` is the photo-annotation
field — `said` is the meal being described, `note` is a photograph being annotated, and the prompt
frames them differently. The response's `photoKey` is null for a described meal.

The Worker verifies the hash and stores the exact model-input bytes in R2 *before* calling the
model, so a provider failure or a cancelled confirmation sheet still leaves a repairable input; an
input that never became a meal is an orphan the Sunday sweep collects.

The cache identity is `(account, input fingerprint, prompt version, model)`. The fingerprint covers
the photo hash, `said`, `note` **and the request's country** — with search on, "subway footlong"
asked from Japan and from the United States are questions with answers 500 kcal apart. D1 holds
metadata and provenance, never image bytes.

Every answer is checked against Atwater — `protein × 4 + carbohydrate × 4 + fat × 9 + alcohol × 7`
within 10% of `kcal` — and any food that disagrees with itself is logged by name. It is a warning
rather than a refusal: the figures are still the best answer there is, and a meal thrown away for
failing arithmetic is a meal somebody has to log again by hand.

### Sync

Two-way, and it merges by id. An event is immutable — the same id is always the same record — so a
union needs no conflict policy and no clock anyone trusts. `POST /events/batch` is insert-or-ignore,
so a phone re-uploading its whole log at launch is normal, cheap and silent; the response is
`{ accepted, inserted, replayed }`.

`GET /events?after=<cursor>&limit=<n≤500>` returns `{ events, cursor }`, oldest first, ordered by
`(recorded_at, id)` — a total order, because `recorded_at` is server-visible and the id is a UUIDv7
that breaks ties identically on every page. `cursor` is null on the last page.

**Each element of `events` is a string**, not an object: the JSON text of the whole envelope, so the
phone appends it to its log without parsing it. `payload` comes back exactly as stored, so an event
this build has never heard of survives the trip untouched. The text is stable under round-trip —
upload what the pull returned and the identical string comes back — though it is not a promise about
the whitespace of the original request, which is retained nowhere.

A meal event is parsed against `mealEventDataSchema` **before anything is written**, and a batch it
cannot read is a 400 naming the field. The server has exactly one job that depends on reading a meal
— knowing which photograph it references, so the orphan sweep does not delete it — and the previous
version of this skipped a meal it could not parse, wrote no `meal_media` row, reported success, and
let the sweep delete the picture a day later.

A `meal_deleted` event purges the meal's `meal_logged`/`meal_revised` rows and releases its
photograph, and the tombstone itself stays: the other phones on the account learn of the deletion by
pulling it, and removing it would let a second device re-upload the meal and undo the deletion.

## One image lifecycle

```text
recognition upload
  └─ media/{account}/{yyyy-mm}/{source-sha}.jpg   the exact bytes the model was sent
```

Deleting a meal tombstones its media reference and removes the object when no other meal uses the
same hash. Account deletion lists the `media/{account}/` prefix, bulk-deletes it, then removes the
D1 rows — identities last, so the next Sign in with Apple is a first sign-in rather than a deleted
account quietly returning as an empty one.

The Sunday cron removes unreferenced media older than 24 hours and expired sessions. The bucket must
remain private — photo reads go through the authenticated Worker route.

## Branded food

`RECOGNITION_SEARCH=on` hands the recognition call `googleSearch` as a tool. The model reaches for it
on a chain's product and ignores it on food nobody published — an ordinary home meal performs no
search and costs nothing extra — and it answers in the same schema either way. A Subway JP American
Clubhouse footlong publishes 698 kcal: ungrounded this prompt answered 845 and 865, grounded it
answers 699.

The request's country goes into the turn with it, from `CF-IPCountry`, as the weakest evidence in the
prompt. Nobody types their own country, and without it the same words returned 1216 kcal —
correctly, for the American sandwich.

What none of this buys is a citation: `generateContent` returns no grounding metadata beside a
response schema, so a grounded figure is `model`, and the app calls it an estimate.

## The one hand-written schema

`geminiResponseSchema()` in `worker/ai/gemini.ts` restates the Zod contract in Gemini's OpenAPI
subset, because Gemini rejects `additionalProperties` and spells nullable as a flag. It emits
*exactly* the properties it names and drops anything else the prompt asks for — which is how a
weighing prompt once shipped against a schema with no `grams`, for a month, with every answer
parsing. `gemini.test.ts` compares it field by field against `mealRecognitionJsonSchema()`, and that
comparison is now the only reason the derived schema exists at all.

`MEAL_PROMPT_VERSION` lives in `worker/ai/prompt.generated.ts` and nowhere else. It was a wrangler
var as well, and the recognition cache keys on it, so a deploy that bumped one and not the other
would either replay the old prompt's answers under the new prompt's name or discard a cache for
nothing. Edit the file under `prompts/` and run `node scripts/sync-prompt.mjs` from the repo root.

## Useful commands

```bash
pnpm db:generate       # regenerate migrations/ from worker/db/schema.ts
pnpm db:migrate:local
pnpm typecheck
pnpm test
pnpm check
pnpm verify
pnpm eval:nutrition    # the whole pipeline against meals whose figures were published
```

Migrations were squashed to a single `0000_init.sql` when the rewrite landed: fourteen files that
built tables, a corpus, food prices and published sources the app no longer has, half of them
existing only to drop the other half. Nothing in the field carries real data, so applying the new
one locally means deleting `.wrangler/state` first.

## Deploying

Authenticate once, then one script does the rest:

```bash
export CLOUDFLARE_API_TOKEN=…   # Workers Scripts: Edit, D1: Edit, R2: Edit, Account Settings: Read
./scripts/bootstrap-remote.sh
```

`wrangler login` works instead of the token. The first run creates the D1 database and the private
`eatsome-media` bucket, then prints the database id; paste that into `wrangler.jsonc` and run it
again, and it sets the secret, migrates, and deploys. It is safe to re-run.

There is nothing per-person to provision and no backend secret in a TestFlight archive. Apple proves
the person's identity during sign-in; the Worker mints a random 256-bit session and the app keeps it
in the Keychain. Sessions expire after 180 days and are revoked per device at sign-out. The Gemini
key is a Worker secret and never reaches the app.
