import type { CorpusItemRequest } from "../../src/contracts";
import { decodeBase64Image, sha256Hex } from "../ai/image";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { deleteAccountMedia } from "./media";
import { deleteTablesData } from "./tables";

export function corpusKey(corpusHash: string): string {
  return `corpus/${corpusHash}.jpg`;
}

async function deleteCorpusObjectIfUnreferenced(env: Env, corpusHash: string): Promise<boolean> {
  const reference = await env.DB.prepare(
    "SELECT 1 AS used FROM corpus_items WHERE corpus_hash = ? LIMIT 1",
  )
    .bind(corpusHash)
    .first<{ used: number }>();
  if (reference) return false;

  const row = await env.DB.prepare(
    "SELECT object_key AS objectKey FROM corpus_objects WHERE corpus_hash = ?",
  )
    .bind(corpusHash)
    .first<{ objectKey: string }>();
  if (!row) return false;
  await env.MEDIA.delete(row.objectKey);
  await env.DB.prepare(
    `DELETE FROM corpus_objects
      WHERE corpus_hash = ?
        AND NOT EXISTS (SELECT 1 FROM corpus_items WHERE corpus_hash = ?)`,
  )
    .bind(corpusHash, corpusHash)
    .run();
  return true;
}

/**
 * Promote a privacy-filtered crop only after the confirmed meal event exists.
 * No server fallback copies `media/`: if the client cannot make the promised
 * crop, the safe result is no corpus item.
 */
export async function addCorpusItem(
  env: Env,
  accountId: string,
  input: CorpusItemRequest,
): Promise<{ corpusHash: string; objectKey: string; cached: boolean }> {
  const sourceHash = input.sourcePhotoHash.toLowerCase();
  const expectedCorpusHash = input.corpusHash.toLowerCase();
  const meal = await env.DB.prepare(
    `SELECT 1 AS found
       FROM meal_media AS meal
       JOIN media_objects AS media
         ON media.account_id = meal.account_id
        AND media.photo_hash = meal.photo_hash
        AND media.stored_at IS NOT NULL
      WHERE meal.account_id = ? AND meal.meal_id = ? AND meal.photo_hash = ?`,
  )
    .bind(accountId, input.mealId, sourceHash)
    .first<{ found: number }>();
  if (!meal) {
    throw new HttpError(409, "Save and sync the meal before adding its corpus image.");
  }

  const bytes = decodeBase64Image(input.imageBase64);
  const actualCorpusHash = await sha256Hex(bytes);
  if (actualCorpusHash !== expectedCorpusHash) {
    throw new HttpError(400, "corpusHash does not match the cropped image bytes.");
  }

  const objectKey = corpusKey(actualCorpusHash);
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO corpus_objects
      (corpus_hash, object_key, mime_type, byte_size, created_at, stored_at)
     VALUES (?, ?, ?, ?, ?, NULL)`,
  )
    .bind(actualCorpusHash, objectKey, input.mimeType, bytes.byteLength, now)
    .run();
  const existing = await env.MEDIA.head(objectKey);
  if (!existing) {
    await env.MEDIA.put(objectKey, bytes, {
      httpMetadata: { contentType: "image/jpeg", cacheControl: "private, no-store" },
      customMetadata: { sha256: actualCorpusHash, purpose: "consented-corpus" },
    });
  }
  await env.DB.prepare(
    "UPDATE corpus_objects SET stored_at = ? WHERE corpus_hash = ? AND stored_at IS NULL",
  )
    .bind(now, actualCorpusHash)
    .run();

  const previous = await env.DB.prepare(
    "SELECT corpus_hash AS corpusHash FROM corpus_items WHERE source_user = ? AND meal_id = ?",
  )
    .bind(accountId, input.mealId)
    .first<{ corpusHash: string }>();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO corpus_items
        (source_user, meal_id, source_photo_hash, corpus_hash,
         consent_policy_version, consent_captured_at, crop_method, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(source_user, meal_id) DO UPDATE SET
         source_photo_hash = excluded.source_photo_hash,
         corpus_hash = excluded.corpus_hash,
         consent_policy_version = excluded.consent_policy_version,
         consent_captured_at = excluded.consent_captured_at,
         crop_method = excluded.crop_method,
         created_at = excluded.created_at`,
    ).bind(
      accountId,
      input.mealId,
      sourceHash,
      actualCorpusHash,
      input.consent.policyVersion,
      input.consent.capturedAt,
      input.privacy.cropMethod,
      now,
    ),
    env.DB.prepare(
      `INSERT INTO corpus_consents (account_id, enabled, policy_version, updated_at)
       VALUES (?, 1, ?, ?)
       ON CONFLICT(account_id) DO UPDATE SET
         enabled = 1,
         policy_version = excluded.policy_version,
         updated_at = excluded.updated_at`,
    ).bind(accountId, input.consent.policyVersion, input.consent.capturedAt),
  ]);

  if (previous && previous.corpusHash !== actualCorpusHash) {
    await deleteCorpusObjectIfUnreferenced(env, previous.corpusHash);
  }
  return { corpusHash: actualCorpusHash, objectKey, cached: Boolean(existing) };
}

/** Remove crop uploads that never acquired a consent/provenance reference. */
export async function deleteOrphanCorpus(
  env: Env,
  olderThan = new Date(Date.now() - 86_400_000),
  limit = 500,
): Promise<number> {
  const rows = await env.DB.prepare(
    `SELECT object.corpus_hash AS corpusHash
       FROM corpus_objects AS object
      WHERE object.created_at < ?
        AND NOT EXISTS (
          SELECT 1 FROM corpus_items AS item
           WHERE item.corpus_hash = object.corpus_hash
        )
      ORDER BY object.created_at
      LIMIT ?`,
  )
    .bind(olderThan.toISOString(), limit)
    .all<{ corpusHash: string }>();
  let deleted = 0;
  for (const row of rows.results) {
    if (await deleteCorpusObjectIfUnreferenced(env, row.corpusHash)) deleted += 1;
  }
  return deleted;
}

/** Retroactive opt-out: remove provenance rows, then unreferenced crop bytes. */
export async function optOutCorpus(
  env: Env,
  accountId: string,
): Promise<{ items: number; objects: number }> {
  const rows = await env.DB.prepare(
    "SELECT corpus_hash AS corpusHash FROM corpus_items WHERE source_user = ?",
  )
    .bind(accountId)
    .all<{ corpusHash: string }>();
  const hashes = [...new Set(rows.results.map((row) => row.corpusHash))];
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM corpus_items WHERE source_user = ?").bind(accountId),
    env.DB.prepare(
      `INSERT INTO corpus_consents (account_id, enabled, policy_version, updated_at)
       VALUES (?, 0, 'opted-out', ?)
       ON CONFLICT(account_id) DO UPDATE SET
         enabled = 0,
         policy_version = excluded.policy_version,
         updated_at = excluded.updated_at`,
    ).bind(accountId, now),
  ]);

  let objects = 0;
  for (const hash of hashes) {
    if (await deleteCorpusObjectIfUnreferenced(env, hash)) objects += 1;
  }
  return { items: rows.results.length, objects };
}

/**
 * Erasure, including both R2 lifecycles and all owned D1 rows.
 *
 * Every partition, not just the one this request wrote under. "Delete my data"
 * from a signed-in phone has to mean the account, or it deletes what that phone
 * happens to have written today and reports success for the rest — which was a
 * true answer while a device was an account, and stopped being one the moment
 * two devices could share one.
 *
 * The identity rows go too, and last. Leaving `identities` behind would resolve
 * a later sign-in to an account whose data is gone but whose id is the same,
 * which is a deleted account quietly coming back as an empty one; the person
 * asked to be forgotten, so the next sign-in should be a first sign-in.
 */
export async function deleteAccountData(
  env: Env,
  partitions: string[],
): Promise<{ mediaObjects: number; corpusItems: number; corpusObjects: number }> {
  let items = 0;
  let objects = 0;
  let mediaObjects = 0;
  // Shared copies are still the person's data: every table post they authored
  // goes too, photo bytes first. See `deleteTablesData` for the argument.
  await deleteTablesData(env, partitions);
  for (const partition of partitions) {
    const corpus = await optOutCorpus(env, partition);
    items += corpus.items;
    objects += corpus.objects;
    mediaObjects += await deleteAccountMedia(env, partition);
  }

  const placeholders = partitions.map(() => "?").join(", ");
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM meal_evals WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM meal_media WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM recognitions WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM media_objects WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM events WHERE account_id IN (${placeholders})`).bind(...partitions),
    env.DB.prepare(`DELETE FROM corpus_consents WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    // Order matters against the foreign keys: sessions, links and identities
    // all point at `accounts`, so the account row can only go last.
    env.DB.prepare(`DELETE FROM sessions WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM account_partitions WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM identities WHERE account_id IN (${placeholders})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM accounts WHERE id IN (${placeholders})`).bind(...partitions),
  ]);
  return { mediaObjects, corpusItems: items, corpusObjects: objects };
}
