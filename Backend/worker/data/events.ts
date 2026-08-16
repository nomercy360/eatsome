import type { EventPullQuery, IngestEventsRequest } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { deletedMealFrom, mealFrom, projectMealMedia } from "./media";

const MAX_BATCH_BYTES = 1_000_000;
const DELETE_CHUNK_SIZE = 50;

/**
 * Append a batch of the phone's log to this account's mirror.
 *
 * Insert-or-ignore by event id, because an event is immutable: the same id is
 * always the same record, so a full re-upload from a phone is normal, cheap and
 * silent. `inserted` counts the rows that were new and `replayed` the rest.
 *
 * Every meal in the batch is parsed **before** anything is written. The server
 * has one job that depends on reading a meal — knowing which photograph it
 * references, so the orphan sweep does not delete it — and a batch it cannot
 * read is a batch whose photographs it is about to lose. Storing the events and
 * failing quietly on the projection is the shape of that loss, so the parse
 * happens first and a bad meal costs the whole batch a 400 rather than costing
 * one picture a day later.
 */
export async function ingestEvents(
  env: Env,
  accountId: string,
  input: IngestEventsRequest,
): Promise<{ accepted: number; inserted: number; replayed: number }> {
  const database = env.DB;
  const bytes = new TextEncoder().encode(JSON.stringify(input)).byteLength;
  if (bytes > MAX_BATCH_BYTES) {
    throw new HttpError(413, "Event batch exceeds the 1 MB request limit.");
  }

  for (const event of input.events) {
    if (event.payload.kind === "meal_logged" || event.payload.kind === "meal_revised") {
      mealFrom(event);
    } else if (event.payload.kind === "meal_deleted") {
      deletedMealFrom(event);
    }
  }

  const receivedAt = new Date().toISOString();
  const statements = input.events.map((event) =>
    database
      .prepare(
        `INSERT INTO events
          (id, account_id, device_id, occurred_at, recorded_at, kind, payload_json, received_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO NOTHING`,
      )
      .bind(
        event.id,
        accountId,
        input.deviceId,
        event.occurredAt,
        event.recordedAt,
        event.payload.kind,
        JSON.stringify(event.payload),
        receivedAt,
      ),
  );

  const results = await database.batch(statements);
  const inserted = results.reduce(
    (count, result) => count + (result.meta.changes === 1 ? 1 : 0),
    0,
  );
  await purgeDeletedMealContent(database, accountId, input.events);
  // The event log remains canonical. This projection is idempotent and applies
  // even on a replay, so a transient R2/D1 failure can be repaired by sending
  // the same event again without inventing a mutable meal endpoint.
  await projectMealMedia(env, accountId, input.events);
  return { accepted: input.events.length, inserted, replayed: input.events.length - inserted };
}

/**
 * A deleted meal's *content* leaves the server; its tombstone does not.
 *
 * Both halves matter and they pull in opposite directions. The content goes
 * because "delete this meal" has to mean the photograph and the figures are
 * gone from the account, not merely hidden. The `meal_deleted` event stays
 * because the other phones on the account learn about the deletion by pulling
 * it — remove the tombstone and a second device re-uploads the meal it still
 * holds, and the meal comes back. It is content-free, so keeping it costs the
 * person nothing they asked to have removed.
 *
 * Idempotent: the local log stays append-only and can replay the same history,
 * and a later tombstone in that replay deletes the content again.
 */
export async function purgeDeletedMealContent(
  database: D1Database,
  accountId: string,
  input: IngestEventsRequest["events"],
): Promise<void> {
  const mealIDs = new Set<string>();
  for (const event of input) {
    if (event.payload.kind === "meal_deleted") mealIDs.add(deletedMealFrom(event));
  }
  if (mealIDs.size === 0) return;

  const ids = [...mealIDs];
  // Keep each D1 batch deliberately small. One request may carry 500 events,
  // while deletion is normally one; chunking prevents a bulk repair from
  // turning into an oversized statement batch.
  for (let start = 0; start < ids.length; start += DELETE_CHUNK_SIZE) {
    await database.batch(
      ids.slice(start, start + DELETE_CHUNK_SIZE).map((mealID) =>
        database
          .prepare(
            `DELETE FROM events
              WHERE account_id = ?
                AND kind IN ('meal_logged', 'meal_revised')
                AND json_extract(payload_json, '$.data.id') = ?`,
          )
          .bind(accountId, mealID),
      ),
    );
  }
}

type Cursor = { recordedAt: number; id: string };

function encodeCursor(cursor: Cursor): string {
  return `${cursor.recordedAt}:${cursor.id}`;
}

function decodeCursor(value: string | undefined): Cursor | null {
  if (!value) return null;
  const separator = value.indexOf(":");
  const recordedAt = Number(value.slice(0, separator));
  const id = value.slice(separator + 1);
  if (separator < 1 || !Number.isSafeInteger(recordedAt) || !id) {
    throw new HttpError(400, "Invalid event cursor.");
  }
  return { recordedAt, id };
}

/**
 * One page of this account's log, oldest first — the pull half of two-way sync.
 *
 * **Each event comes back as a string, not an object**, and the string is the
 * JSON text of the whole envelope. That is the point of the endpoint: the phone
 * appends the string to its log file and is done, without a parse, a re-encode,
 * or an opinion about what is inside. An event this build has never heard of
 * survives the trip for the same reason a photograph survives R2 — nothing on
 * the path looks at it.
 *
 * What "unmodified" honestly means here: `payload` is returned exactly as it
 * was stored, character for character, and the three envelope scalars around it
 * are re-emitted in a fixed order. So the text is not guaranteed to match the
 * client's original bytes if the client sent them pretty-printed or with the
 * envelope keys in another order — the *whitespace* of a request is not
 * retained anywhere. It is guaranteed to be stable under round-trip: upload
 * what this returns and it stores and returns the identical string, so a phone
 * can keep it verbatim forever and never see it change.
 *
 * The order is `(recorded_at, id)` and the cursor is that pair, which is a
 * total order — `recorded_at` is server-visible and the id is a UUIDv7 that
 * breaks ties identically on every page, so paging can neither skip a row nor
 * repeat one. `cursor` comes back null on the last page.
 *
 * Scope is the account, so a phone pulls what every other phone on the account
 * uploaded. That is the whole feature.
 */
export async function pullEvents(
  database: D1Database,
  accountId: string,
  query: EventPullQuery,
): Promise<{ events: string[]; cursor: string | null }> {
  const after = decodeCursor(query.after);
  const statement = after
    ? database
        .prepare(
          `SELECT id, occurred_at AS occurredAt, recorded_at AS recordedAt,
                  payload_json AS payloadJson
             FROM events
            WHERE account_id = ?
              AND (recorded_at > ? OR (recorded_at = ? AND id > ?))
            ORDER BY recorded_at, id
            LIMIT ?`,
        )
        .bind(accountId, after.recordedAt, after.recordedAt, after.id, query.limit)
    : database
        .prepare(
          `SELECT id, occurred_at AS occurredAt, recorded_at AS recordedAt,
                  payload_json AS payloadJson
             FROM events
            WHERE account_id = ?
            ORDER BY recorded_at, id
            LIMIT ?`,
        )
        .bind(accountId, query.limit);

  const page = await statement.all<{
    id: string;
    occurredAt: number;
    recordedAt: number;
    payloadJson: string;
  }>();
  const rows = page.results;
  const last = rows.at(-1);
  return {
    // Built by concatenation rather than by `JSON.stringify` of a parsed
    // object: parsing `payloadJson` to put it back would re-serialise whatever
    // is inside it, and re-serialising something nobody read is how a field
    // this build does not know about comes back subtly different.
    events: rows.map(
      (row) =>
        `{"id":${JSON.stringify(row.id)},"occurredAt":${row.occurredAt},` +
        `"recordedAt":${row.recordedAt},"payload":${row.payloadJson}}`,
    ),
    cursor:
      rows.length === query.limit && last
        ? encodeCursor({ recordedAt: last.recordedAt, id: last.id })
        : null,
  };
}
