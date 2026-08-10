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
import type { LoggedEventInput, MealRecognitionPayload } from "../../src/contracts";

/**
 * One person's account. Its `id` is itself a partition key — the same kind of
 * string as `device:<uuid>` — so an account is a place rows can be written,
 * not a level of indirection above one.
 *
 * That is what keeps the merge below from ever touching a stored row.
 */
export const accounts = sqliteTable("accounts", {
  /** `acct:<uuidv7>`, and it appears verbatim in `events.account_id`. */
  id: text().primaryKey(),
  createdAt: integer("created_at").notNull(),
});

/**
 * Provider plus subject, resolved to an account. Two rows per person is the
 * normal case rather than a conflict: Apple and Google both issue a `sub` for
 * the same human, and both should land on the same account.
 *
 * The subject is the only claim stored. An email is a label a provider will
 * happily move between accounts — Apple's private relay addresses change, and
 * Google's are reassignable within a workspace — so identifying on one is how a
 * stranger inherits somebody's history.
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
 * The merge, and the whole of it: a device partition adopted by an account.
 *
 * Every row already written carries the partition it was written under, and
 * nothing here changes that. Reading as an account means reading the union of
 * its own partition and every device partition linked to it, which is why the
 * merge is one INSERT rather than an UPDATE across four tables — see the long
 * argument in `data/accounts.ts`.
 *
 * `partition_id` is the primary key, not `(partition_id, account_id)`. A device
 * belongs to exactly one account forever; the first sign-in wins, and a later
 * one against a different identity is reported as a conflict rather than
 * quietly moving history off the first account.
 */
export const accountPartitions = sqliteTable(
  "account_partitions",
  {
    /** `device:<uuid>`. Never an `ip:` key — those are refused before here. */
    partitionId: text("partition_id").primaryKey(),
    accountId: text("account_id")
      .notNull()
      .references(() => accounts.id),
    linkedAt: integer("linked_at").notNull(),
  },
  (table) => [index("account_partitions_account_idx").on(table.accountId)],
);

/**
 * What the phone sends instead of re-proving its identity on every request.
 *
 * Apple's identity token lives about ten minutes and cannot be refreshed
 * without another Face ID prompt, so it is a sign-in credential and not a
 * session credential. Only the SHA-256 of the token is stored: a leaked
 * database dump is then a list of hashes rather than a set of working logins.
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
    result: text("result_json", { mode: "json" }).$type<MealRecognitionPayload>().notNull(),
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

/**
 * Tables — a small group feed of shared meals. See `migrations/0008_tables.sql`
 * for the load-bearing decisions; the short form: members are public as a
 * per-table `member_id` and a typed display name, never as a partition string;
 * posts are copies redacted at share time; `seq` is the server-assigned order.
 */
export const socialTables = sqliteTable(
  "tables",
  {
    id: text().primaryKey(),
    name: text().notNull(),
    creatorAccount: text("creator_account").notNull(),
    inviteCode: text("invite_code").notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [uniqueIndex("tables_invite_idx").on(table.inviteCode)],
);

export const tableMembers = sqliteTable(
  "table_members",
  {
    tableId: text("table_id").notNull(),
    accountId: text("account_id").notNull(),
    memberId: text("member_id").notNull(),
    displayName: text("display_name").notNull(),
    role: text().notNull(),
    joinedAt: integer("joined_at").notNull(),
    lastReadSeq: integer("last_read_seq").notNull().default(0),
  },
  (table) => [
    primaryKey({ columns: [table.tableId, table.accountId] }),
    uniqueIndex("table_members_member_idx").on(table.tableId, table.memberId),
    index("table_members_account_idx").on(table.accountId),
    check("table_members_role_check", sql`${table.role} IN ('creator', 'member')`),
  ],
);

export const tablePosts = sqliteTable(
  "table_posts",
  {
    id: text().primaryKey(),
    tableId: text("table_id").notNull(),
    seq: integer().notNull(),
    authorAccount: text("author_account").notNull(),
    authorMemberId: text("author_member_id").notNull(),
    /** Denormalized on purpose: a post is an utterance, and it keeps saying who
     *  said it even after they leave the table. */
    authorName: text("author_name").notNull(),
    kind: text().notNull(),
    replyToPostId: text("reply_to_post_id"),
    mealId: text("meal_id"),
    dishName: text("dish_name"),
    body: text(),
    ingredientsJson: text("ingredients_json"),
    photoObjectKey: text("photo_object_key"),
    photoMime: text("photo_mime"),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [
    uniqueIndex("table_posts_seq_idx").on(table.tableId, table.seq),
    index("table_posts_author_idx").on(table.authorAccount),
    check("table_posts_kind_check", sql`${table.kind} IN ('share', 'message')`),
    check(
      "table_posts_ingredients_check",
      sql`${table.ingredientsJson} IS NULL OR json_valid(${table.ingredientsJson})`,
    ),
  ],
);

export const tableReactions = sqliteTable(
  "table_reactions",
  {
    postId: text("post_id").notNull(),
    accountId: text("account_id").notNull(),
    kind: text().notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.postId, table.accountId, table.kind] }),
    index("table_reactions_account_idx").on(table.accountId),
    check("table_reactions_kind_check", sql`${table.kind} IN ('olive', 'heart')`),
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
