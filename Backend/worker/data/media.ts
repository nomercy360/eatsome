import type { IngestEventsRequest } from "../../src/contracts";
import { mealDeleteDataSchema, mealEventDataSchema } from "../../src/contracts";
import type { Env } from "../env";

export type MediaObject = {
  accountId: string;
  photoHash: string;
  objectKey: string;
  mimeType: string;
  byteSize: number;
  createdAt: string;
  storedAt: string | null;
};

function extensionFor(mimeType: string): string {
  if (mimeType === "image/png") return "png";
  if (mimeType === "image/webp") return "webp";
  return "jpg";
}

export function mediaPrefix(accountId: string): string {
  return `media/${encodeURIComponent(accountId)}/`;
}

export function mediaKey(
  accountId: string,
  photoHash: string,
  mimeType: string,
  now = new Date(),
): string {
  const month = now.toISOString().slice(0, 7);
  return `${mediaPrefix(accountId)}${month}/${photoHash}.${extensionFor(mimeType)}`;
}

async function findMedia(
  database: D1Database,
  accountId: string,
  photoHash: string,
): Promise<MediaObject | null> {
  return findMediaIn(database, [accountId], photoHash);
}

/**
 * The same lookup across every partition an account owns.
 *
 * Multi-device sync hands the second phone a meal whose photograph was uploaded
 * by the first, under the first device's partition. Without this the events
 * arrive and every picture in the history 404s, which reads as data loss.
 * `stored_at` still gates it, so a reserved-but-unwritten row is invisible
 * exactly as before.
 */
async function findMediaIn(
  database: D1Database,
  partitions: string[],
  photoHash: string,
): Promise<MediaObject | null> {
  const placeholders = partitions.map(() => "?").join(", ");
  return database
    .prepare(
      `SELECT account_id AS accountId, photo_hash AS photoHash, object_key AS objectKey,
              mime_type AS mimeType, byte_size AS byteSize, created_at AS createdAt,
              stored_at AS storedAt
         FROM media_objects
        WHERE account_id IN (${placeholders}) AND photo_hash = ?
        ORDER BY stored_at IS NULL, created_at
        LIMIT 1`,
    )
    .bind(...partitions, photoHash)
    .first<MediaObject>();
}

/**
 * Persist the exact bytes sent to the model, once per user/photo.
 *
 * The D1 row is created before R2 so an interrupted PUT is repairable. R2 is
 * strongly consistent, and a retry HEADs the recorded key before writing.
 */
export async function ensureMediaObject(
  env: Env,
  accountId: string,
  photoHash: string,
  mimeType: string,
  bytes: Uint8Array,
  now = new Date(),
): Promise<MediaObject> {
  let media = await findMedia(env.DB, accountId, photoHash);
  if (!media) {
    const createdAt = now.toISOString();
    const objectKey = mediaKey(accountId, photoHash, mimeType, now);
    await env.DB.prepare(
      `INSERT OR IGNORE INTO media_objects
        (account_id, photo_hash, object_key, mime_type, byte_size, created_at, stored_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL)`,
    )
      .bind(accountId, photoHash, objectKey, mimeType, bytes.byteLength, createdAt)
      .run();
    media = await findMedia(env.DB, accountId, photoHash);
  }
  if (!media) throw new Error("Could not reserve media storage.");

  const existing = await env.MEDIA.head(media.objectKey);
  if (!existing) {
    await env.MEDIA.put(media.objectKey, bytes, {
      httpMetadata: {
        contentType: mimeType,
        cacheControl: "private, no-store",
      },
      customMetadata: {
        sha256: photoHash,
        purpose: "model-input",
      },
    });
  }

  if (!media.storedAt) {
    const storedAt = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE media_objects SET stored_at = ?
        WHERE account_id = ? AND photo_hash = ?`,
    )
      .bind(storedAt, accountId, photoHash)
      .run();
    media = { ...media, storedAt };
  }
  return media;
}

export async function getMediaObject(
  env: Env,
  partitions: string[],
  photoHash: string,
): Promise<R2ObjectBody | null> {
  const media = await findMediaIn(env.DB, partitions, photoHash);
  if (!media?.storedAt) return null;
  return env.MEDIA.get(media.objectKey);
}

export async function getStoredMediaInput(
  env: Env,
  accountId: string,
  photoHash: string,
): Promise<{ media: MediaObject; bytes: Uint8Array } | null> {
  const media = await findMedia(env.DB, accountId, photoHash);
  if (!media?.storedAt) return null;
  const object = await env.MEDIA.get(media.objectKey);
  if (!object) return null;
  return { media, bytes: new Uint8Array(await object.arrayBuffer()) };
}

async function currentMealHash(
  database: D1Database,
  accountId: string,
  mealId: string,
): Promise<string | null> {
  const row = await database
    .prepare("SELECT photo_hash AS photoHash FROM meal_media WHERE account_id = ? AND meal_id = ?")
    .bind(accountId, mealId)
    .first<{ photoHash: string | null }>();
  return row?.photoHash ?? null;
}

async function storeMealState(
  database: D1Database,
  accountId: string,
  mealId: string,
  photoHash: string | null,
  eventId: string,
  recordedAt: number,
): Promise<void> {
  await database
    .prepare(
      `INSERT INTO meal_media (account_id, meal_id, photo_hash, event_id, recorded_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(account_id, meal_id) DO UPDATE SET
         photo_hash = excluded.photo_hash,
         event_id = excluded.event_id,
         recorded_at = excluded.recorded_at
       WHERE excluded.recorded_at > meal_media.recorded_at
          OR (excluded.recorded_at = meal_media.recorded_at AND excluded.event_id > meal_media.event_id)`,
    )
    .bind(accountId, mealId, photoHash, eventId, recordedAt)
    .run();
}

export async function deleteMediaIfUnreferenced(
  env: Env,
  accountId: string,
  photoHash: string,
): Promise<boolean> {
  const referenced = await env.DB.prepare(
    "SELECT 1 AS used FROM meal_media WHERE account_id = ? AND photo_hash = ? LIMIT 1",
  )
    .bind(accountId, photoHash)
    .first<{ used: number }>();
  if (referenced) return false;

  const media = await findMedia(env.DB, accountId, photoHash);
  if (!media) return false;
  await env.MEDIA.delete(media.objectKey);
  await env.DB.prepare(
    `DELETE FROM media_objects
      WHERE account_id = ? AND photo_hash = ?
        AND NOT EXISTS (
          SELECT 1 FROM meal_media
           WHERE account_id = ? AND photo_hash = ?
        )`,
  )
    .bind(accountId, photoHash, accountId, photoHash)
    .run();
  return true;
}

/** Project append-only meal events into media references and apply deletion. */
export async function projectMealMedia(
  env: Env,
  accountId: string,
  events: IngestEventsRequest["events"],
): Promise<void> {
  const candidates = new Set<string>();
  for (const event of events) {
    if (event.payload.kind === "meal_logged" || event.payload.kind === "meal_revised") {
      const meal = mealEventDataSchema.safeParse(event.payload.data);
      if (!meal.success) continue;
      const oldHash = await currentMealHash(env.DB, accountId, meal.data.id);
      const photoHash = meal.data.photoHash?.toLowerCase() ?? null;
      await storeMealState(env.DB, accountId, meal.data.id, photoHash, event.id, event.recordedAt);
      if (oldHash && oldHash !== photoHash) candidates.add(oldHash);
      continue;
    }
    if (event.payload.kind === "meal_deleted") {
      const deleted = mealDeleteDataSchema.safeParse(event.payload.data);
      if (!deleted.success) continue;
      const oldHash = await currentMealHash(env.DB, accountId, deleted.data.mealID);
      await storeMealState(
        env.DB,
        accountId,
        deleted.data.mealID,
        null,
        event.id,
        event.recordedAt,
      );
      if (oldHash) candidates.add(oldHash);
    }
  }

  for (const photoHash of candidates) {
    await deleteMediaIfUnreferenced(env, accountId, photoHash);
  }
}

/** Weekly cleanup for recognition uploads that never became saved meals. */
export async function deleteOrphanMedia(
  env: Env,
  olderThan = new Date(Date.now() - 86_400_000),
  limit = 500,
): Promise<number> {
  const rows = await env.DB.prepare(
    `SELECT account_id AS accountId, photo_hash AS photoHash
       FROM media_objects AS media
      WHERE media.created_at < ?
        AND NOT EXISTS (
          SELECT 1 FROM meal_media AS ref
           WHERE ref.account_id = media.account_id
             AND ref.photo_hash = media.photo_hash
        )
      ORDER BY media.created_at
      LIMIT ?`,
  )
    .bind(olderThan.toISOString(), limit)
    .all<{ accountId: string; photoHash: string }>();

  let deleted = 0;
  for (const row of rows.results) {
    if (await deleteMediaIfUnreferenced(env, row.accountId, row.photoHash)) deleted += 1;
  }
  return deleted;
}

/** Prefix deletion is why media keys are partitioned by account. */
export async function deleteAccountMedia(env: Env, accountId: string): Promise<number> {
  const prefix = mediaPrefix(accountId);
  let deleted = 0;
  while (true) {
    // Always restart at the beginning: deleting a page mutates the listing, so
    // carrying its old cursor risks stepping over keys that shifted left.
    const page = await env.MEDIA.list({ prefix, limit: 1_000 });
    const keys = page.objects.map((object) => object.key);
    if (keys.length === 0) break;
    await env.MEDIA.delete(keys);
    deleted += keys.length;
  }
  return deleted;
}
