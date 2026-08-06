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
    photoHash: text("photo_hash").notNull(),
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
    check("recognitions_hash_check", sql`length(${table.photoHash}) = 64`),
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

/** Cropped corpus bytes are content-addressed independently from media bytes. */
export const corpusObjects = sqliteTable(
  "corpus_objects",
  {
    corpusHash: text("corpus_hash").primaryKey(),
    objectKey: text("object_key").notNull(),
    mimeType: text("mime_type").notNull(),
    byteSize: integer("byte_size").notNull(),
    createdAt: text("created_at").notNull(),
    storedAt: text("stored_at"),
  },
  (table) => [
    uniqueIndex("corpus_objects_key_idx").on(table.objectKey),
    index("corpus_objects_orphans_idx").on(table.createdAt, table.storedAt),
    check("corpus_objects_hash_check", sql`length(${table.corpusHash}) = 64`),
    check("corpus_objects_size_check", sql`${table.byteSize} >= 0`),
  ],
);

/** One provenance/consent reference per source user's confirmed meal. */
export const corpusItems = sqliteTable(
  "corpus_items",
  {
    accountId: text("source_user").notNull(),
    mealId: text("meal_id").notNull(),
    sourcePhotoHash: text("source_photo_hash").notNull(),
    corpusHash: text("corpus_hash").notNull(),
    consentPolicyVersion: text("consent_policy_version").notNull(),
    consentCapturedAt: integer("consent_captured_at").notNull(),
    cropMethod: text("crop_method").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.accountId, table.mealId] }),
    index("corpus_items_user_idx").on(table.accountId),
    index("corpus_items_object_idx").on(table.corpusHash),
    check("corpus_items_source_hash_check", sql`length(${table.sourcePhotoHash}) = 64`),
    check("corpus_items_corpus_hash_check", sql`length(${table.corpusHash}) = 64`),
  ],
);

export const corpusConsents = sqliteTable("corpus_consents", {
  accountId: text("account_id").primaryKey(),
  enabled: integer({ mode: "boolean" }).notNull(),
  policyVersion: text("policy_version").notNull(),
  updatedAt: integer("updated_at").notNull(),
});

/** Revocable development access. Raw invite tokens are never stored. */
export const friendInviteTokens = sqliteTable(
  "friend_invite_tokens",
  {
    tokenHash: text("token_hash").primaryKey(),
    accountId: text("account_id").notNull(),
    label: text().notNull(),
    createdAt: integer("created_at").notNull(),
    revokedAt: integer("revoked_at"),
  },
  (table) => [
    index("friend_invite_tokens_account_idx").on(table.accountId, table.revokedAt),
    index("friend_invite_tokens_label_idx").on(table.label, table.revokedAt),
    check("friend_invite_tokens_hash_check", sql`length(${table.tokenHash}) = 64`),
  ],
);

export const mealEvals = sqliteTable(
  "meal_evals",
  {
    eventId: text("event_id")
      .primaryKey()
      .references(() => events.id, { onDelete: "cascade" }),
    accountId: text("account_id").notNull(),
    deviceId: text("device_id").notNull(),
    mealId: text("meal_id").notNull(),
    photoHash: text("photo_hash").notNull(),
    promptVersion: text("prompt_version").notNull(),
    rawModelJson: text("raw_model_json").notNull(),
    initialItems: text("initial_items_json", { mode: "json" }).$type<unknown[]>().notNull(),
    finalItems: text("final_items_json", { mode: "json" }).$type<unknown[]>().notNull(),
    otherMealsVisible: integer("other_meals_visible", { mode: "boolean" }).notNull(),
    wasCorrected: integer("was_corrected", { mode: "boolean" }).notNull(),
    recordedAt: integer("recorded_at").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [
    index("meal_evals_account_created_idx").on(table.accountId, table.createdAt),
    index("meal_evals_prompt_idx").on(table.promptVersion, table.createdAt),
    index("meal_evals_meal_idx").on(table.mealId, table.recordedAt),
    check("meal_evals_initial_json_check", sql`json_valid(${table.initialItems})`),
    check("meal_evals_final_json_check", sql`json_valid(${table.finalItems})`),
    check("meal_evals_raw_json_check", sql`json_valid(${table.rawModelJson})`),
    check("meal_evals_hash_check", sql`length(${table.photoHash}) = 64`),
  ],
);
