import { and, asc, eq, gt, or } from "drizzle-orm";
import { type IngestEventsRequest, mealEventDataSchema } from "../../src/contracts";
import { createDb } from "../db/client";
import { events, mealEvals } from "../db/schema";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { projectMealMedia } from "./media";

const MAX_BATCH_BYTES = 1_000_000;

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

  const receivedAt = new Date().toISOString();
  const statements: D1PreparedStatement[] = [];
  const eventStatementIndexes: number[] = [];

  for (const event of input.events) {
    eventStatementIndexes.push(statements.length);
    statements.push(
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

    if (event.payload.kind !== "meal_logged" && event.payload.kind !== "meal_revised") continue;
    const meal = mealEventDataSchema.safeParse(event.payload.data);
    if (!meal.success || !meal.data.photoHash || !meal.data.recognitionEvidence) continue;
    const evidence = meal.data.recognitionEvidence;
    statements.push(
      database
        .prepare(
          `INSERT INTO meal_evals
            (event_id, account_id, device_id, meal_id, photo_hash, prompt_version,
             raw_model_json, initial_items_json, final_items_json, other_meals_visible,
             was_corrected, recorded_at, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(event_id) DO NOTHING`,
        )
        .bind(
          event.id,
          accountId,
          input.deviceId,
          meal.data.id,
          meal.data.photoHash.toLowerCase(),
          evidence.promptVersion,
          evidence.rawModelJSON,
          JSON.stringify(evidence.initialItems),
          JSON.stringify(meal.data.items),
          evidence.otherMealsVisible ? 1 : 0,
          meal.data.wasCorrected ? 1 : 0,
          event.recordedAt,
          receivedAt,
        ),
    );
  }

  const results = await database.batch(statements);
  const inserted = eventStatementIndexes.reduce((count, index) => {
    return count + (results[index]?.meta.changes === 1 ? 1 : 0);
  }, 0);
  // The event log remains canonical. This projection is idempotent and applies
  // even on a replay, so a transient R2/D1 failure can be repaired by sending
  // the same event again without inventing a mutable meal endpoint.
  await projectMealMedia(env, accountId, input.events);
  return { accepted: input.events.length, inserted, replayed: input.events.length - inserted };
}

export async function listEvents(
  database: D1Database,
  accountId: string,
  cursorValue: string | undefined,
  limit: number,
) {
  const cursor = decodeCursor(cursorValue);
  const db = createDb(database);
  const cursorCondition = cursor
    ? or(
        gt(events.recordedAt, cursor.recordedAt),
        and(eq(events.recordedAt, cursor.recordedAt), gt(events.id, cursor.id)),
      )
    : undefined;
  const rows = await db.query.events.findMany({
    where: cursorCondition
      ? and(eq(events.accountId, accountId), cursorCondition)
      : eq(events.accountId, accountId),
    orderBy: [asc(events.recordedAt), asc(events.id)],
    limit,
  });
  const last = rows.at(-1);
  return {
    events: rows.map((row) => ({
      id: row.id,
      occurredAt: row.occurredAt,
      recordedAt: row.recordedAt,
      payload: row.payload,
      sourceDeviceId: row.deviceId,
    })),
    nextCursor: last
      ? encodeCursor({ recordedAt: last.recordedAt, id: last.id })
      : (cursorValue ?? null),
  };
}

export async function listMealEvals(database: D1Database, accountId: string, limit: number) {
  const db = createDb(database);
  return db.query.mealEvals.findMany({
    where: eq(mealEvals.accountId, accountId),
    orderBy: [asc(mealEvals.createdAt)],
    limit,
  });
}
