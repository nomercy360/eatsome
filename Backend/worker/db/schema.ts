import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";
import type { LoggedEventInput, MealRecognition } from "../../src/contracts";

/**
 * One person's account, and the whole of what the server keeps about them.
 *
 * `accounts.id` is `acct:<uuidv7>` and it appears verbatim in every
 * `account_id` column. There is no second kind of partition and no union to
 * read over: a request either carries a verified session or it is a 401, so
 * every read is `WHERE account_id = ?` against one string.
 */
export const accounts = sqliteTable("accounts", {
  id: text().primaryKey(),
  createdAt: integer("created_at").notNull(),
});

/**
 * Provider subject resolved to an account.
 *
 * The subject is the only claim stored. An email is a label a provider will
 * happily move between accounts — Apple's private relay addresses change — so
 * identifying on one is how a stranger inherits somebody's history.
 */
export const identities = sqliteTable(
  "identities",
  {
    provider: text().notNull(),
    subject: text().notNull(),
    accountId: text("account_id")
      .notNull()
      .references(() => accounts.id),
    /** Recorded once, at first sign-in, for support. Never used to identify. */
    email: text(),
    emailVerified: integer("email_verified", { mode: "boolean" }).notNull().default(false),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.provider, table.subject] }),
    index("identities_account_idx").on(table.accountId),
  ],
);

/**
 * What the phone sends instead of re-proving its identity on every request.
 *
 * Apple's identity token lives about ten minutes and cannot be refreshed without
 * another Face ID prompt, so it is a sign-in credential and not a session
 * credential. Only the SHA-256 of the session token is stored: a leaked database
 * dump is then a list of hashes rather than a set of working logins.
 */
export const sessions = sqliteTable(
  "sessions",
  {
    tokenHash: text("token_hash").primaryKey(),
    accountId: text("account_id")
      .notNull()
      .references(() => accounts.id),
    /** Which phone holds it, so one device can be signed out on its own. */
    deviceId: text("device_id").notNull(),
    createdAt: integer("created_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [index("sessions_account_idx").on(table.accountId, table.expiresAt)],
);

export const events = sqliteTable(
  "events",
  {
    id: text().primaryKey(),
    accountId: text("account_id").notNull(),
    deviceId: text("device_id").notNull(),
    occurredAt: integer("occurred_at").notNull(),
    recordedAt: integer("recorded_at").notNull(),
    kind: text().notNull(),
    payload: text("payload_json", { mode: "json" }).$type<LoggedEventInput["payload"]>().notNull(),
    receivedAt: text("received_at").notNull(),
  },
  (table) => [
    index("events_account_cursor_idx").on(table.accountId, table.recordedAt, table.id),
    index("events_account_kind_idx").on(table.accountId, table.kind, table.recordedAt),
    check("events_payload_json_check", sql`json_valid(${table.payload})`),
  ],
);

export const recognitions = sqliteTable(
  "recognitions",
  {
    id: text().primaryKey(),
    accountId: text("account_id").notNull(),
    /** Null for a meal that was described rather than photographed. */
    photoHash: text("photo_hash"),
    inputFingerprint: text("input_fingerprint").notNull(),
    promptVersion: text("prompt_version").notNull(),
    model: text().notNull(),
    result: text("result_json", { mode: "json" }).$type<MealRecognition>().notNull(),
    rawModelJson: text("raw_model_json").notNull(),
    providerRequestId: text("provider_request_id"),
    inputTokens: integer("input_tokens").notNull().default(0),
    outputTokens: integer("output_tokens").notNull().default(0),
    latencyMs: integer("latency_ms").notNull().default(0),
    createdAt: text("created_at").notNull(),
  },
  (table) => [
    uniqueIndex("recognitions_cache_idx").on(
      table.accountId,
      table.inputFingerprint,
      table.promptVersion,
      table.model,
    ),
    index("recognitions_account_created_idx").on(table.accountId, table.createdAt),
    check("recognitions_result_json_check", sql`json_valid(${table.result})`),
    check("recognitions_raw_json_check", sql`json_valid(${table.rawModelJson})`),
    check(
      "recognitions_hash_check",
      sql`${table.photoHash} IS NULL OR length(${table.photoHash}) = 64`,
    ),
    check("recognitions_input_tokens_check", sql`${table.inputTokens} >= 0`),
    check("recognitions_output_tokens_check", sql`${table.outputTokens} >= 0`),
    check("recognitions_latency_check", sql`${table.latencyMs} >= 0`),
  ],
);

/** The exact model-input bytes retained from first recognition. */
export const mediaObjects = sqliteTable(
  "media_objects",
  {
    accountId: text("account_id").notNull(),
    photoHash: text("photo_hash").notNull(),
    objectKey: text("object_key").notNull(),
    mimeType: text("mime_type").notNull(),
    byteSize: integer("byte_size").notNull(),
    createdAt: text("created_at").notNull(),
    storedAt: text("stored_at"),
  },
  (table) => [
    primaryKey({ columns: [table.accountId, table.photoHash] }),
    uniqueIndex("media_objects_key_idx").on(table.objectKey),
    index("media_objects_orphans_idx").on(table.createdAt, table.storedAt),
    check("media_objects_hash_check", sql`length(${table.photoHash}) = 64`),
    check("media_objects_size_check", sql`${table.byteSize} >= 0`),
  ],
);

/**
 * Latest photo state per meal. A null hash is a deletion tombstone, so replaying
 * an older meal_logged event cannot resurrect a media reference.
 */
export const mealMedia = sqliteTable(
  "meal_media",
  {
    accountId: text("account_id").notNull(),
    mealId: text("meal_id").notNull(),
    photoHash: text("photo_hash"),
    eventId: text("event_id").notNull(),
    recordedAt: integer("recorded_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.accountId, table.mealId] }),
    index("meal_media_reference_idx").on(table.accountId, table.photoHash),
  ],
);

/**
 * The day's paid-call reservation.
 *
 * Reading a count and then spending is a time-of-check race: under load every
 * request sees 399 and every one of them proceeds. D1 serialises writes, so a
 * conditional UPDATE against this row is a real reservation. It has always
 * existed in `migrations/`; it belongs in the schema too, or `drizzle-kit
 * generate` proposes creating it on every run.
 */
export const budget = sqliteTable("budget", {
  /** `YYYY-MM-DD`, UTC. */
  day: text().primaryKey(),
  used: integer().notNull().default(0),
});
