-- The whole schema, in one statement list.
--
-- Fourteen migrations preceded this one and none of them survives: they built
-- tables, corpora, food prices, published sources and a social feed that the
-- rewrite does not have, and half of them existed only to drop the other half.
-- There is no database in the field carrying real data — every install is a
-- test account — so a migration history recording how we got somewhere nobody
-- is has no reader. This is generated from `worker/db/schema.ts` by
-- `pnpm db:generate`, and `drizzle-kit` will keep diffing against it.
--
-- Applying it to an existing local D1 means deleting `.wrangler/state` first.
CREATE TABLE `accounts` (
	`id` text PRIMARY KEY NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `budget` (
	`day` text PRIMARY KEY NOT NULL,
	`used` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`device_id` text NOT NULL,
	`occurred_at` integer NOT NULL,
	`recorded_at` integer NOT NULL,
	`kind` text NOT NULL,
	`payload_json` text NOT NULL,
	`received_at` text NOT NULL,
	CONSTRAINT "events_payload_json_check" CHECK(json_valid("events"."payload_json"))
);
--> statement-breakpoint
CREATE INDEX `events_account_cursor_idx` ON `events` (`account_id`,`recorded_at`,`id`);--> statement-breakpoint
CREATE INDEX `events_account_kind_idx` ON `events` (`account_id`,`kind`,`recorded_at`);--> statement-breakpoint
CREATE TABLE `identities` (
	`provider` text NOT NULL,
	`subject` text NOT NULL,
	`account_id` text NOT NULL,
	`email` text,
	`email_verified` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`provider`, `subject`),
	FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `identities_account_idx` ON `identities` (`account_id`);--> statement-breakpoint
CREATE TABLE `meal_media` (
	`account_id` text NOT NULL,
	`meal_id` text NOT NULL,
	`photo_hash` text,
	`event_id` text NOT NULL,
	`recorded_at` integer NOT NULL,
	PRIMARY KEY(`account_id`, `meal_id`)
);
--> statement-breakpoint
CREATE INDEX `meal_media_reference_idx` ON `meal_media` (`account_id`,`photo_hash`);--> statement-breakpoint
CREATE TABLE `media_objects` (
	`account_id` text NOT NULL,
	`photo_hash` text NOT NULL,
	`object_key` text NOT NULL,
	`mime_type` text NOT NULL,
	`byte_size` integer NOT NULL,
	`created_at` text NOT NULL,
	`stored_at` text,
	PRIMARY KEY(`account_id`, `photo_hash`),
	CONSTRAINT "media_objects_hash_check" CHECK(length("media_objects"."photo_hash") = 64),
	CONSTRAINT "media_objects_size_check" CHECK("media_objects"."byte_size" >= 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `media_objects_key_idx` ON `media_objects` (`object_key`);--> statement-breakpoint
CREATE INDEX `media_objects_orphans_idx` ON `media_objects` (`created_at`,`stored_at`);--> statement-breakpoint
CREATE TABLE `recognitions` (
	`id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`photo_hash` text,
	`input_fingerprint` text NOT NULL,
	`prompt_version` text NOT NULL,
	`model` text NOT NULL,
	`result_json` text NOT NULL,
	`raw_model_json` text NOT NULL,
	`provider_request_id` text,
	`input_tokens` integer DEFAULT 0 NOT NULL,
	`output_tokens` integer DEFAULT 0 NOT NULL,
	`latency_ms` integer DEFAULT 0 NOT NULL,
	`created_at` text NOT NULL,
	CONSTRAINT "recognitions_result_json_check" CHECK(json_valid("recognitions"."result_json")),
	CONSTRAINT "recognitions_raw_json_check" CHECK(json_valid("recognitions"."raw_model_json")),
	CONSTRAINT "recognitions_hash_check" CHECK("recognitions"."photo_hash" IS NULL OR length("recognitions"."photo_hash") = 64),
	CONSTRAINT "recognitions_input_tokens_check" CHECK("recognitions"."input_tokens" >= 0),
	CONSTRAINT "recognitions_output_tokens_check" CHECK("recognitions"."output_tokens" >= 0),
	CONSTRAINT "recognitions_latency_check" CHECK("recognitions"."latency_ms" >= 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `recognitions_cache_idx` ON `recognitions` (`account_id`,`input_fingerprint`,`prompt_version`,`model`);--> statement-breakpoint
CREATE INDEX `recognitions_account_created_idx` ON `recognitions` (`account_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`device_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `sessions_account_idx` ON `sessions` (`account_id`,`expires_at`);
