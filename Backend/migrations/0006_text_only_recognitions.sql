-- A meal typed or dictated has no photograph, so its recognition row has no
-- photo hash. SQLite cannot loosen NOT NULL in place; rebuild the table with
-- the column nullable and the length check scoped to rows that have one. The
-- cache key was already `input_fingerprint`, which covers the text, so nothing
-- about lookups changes.
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_recognitions` (
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
	CONSTRAINT "recognitions_result_json_check" CHECK(json_valid("result_json")),
	CONSTRAINT "recognitions_raw_json_check" CHECK(json_valid("raw_model_json")),
	CONSTRAINT "recognitions_hash_check" CHECK("photo_hash" IS NULL OR length("photo_hash") = 64),
	CONSTRAINT "recognitions_input_tokens_check" CHECK("input_tokens" >= 0),
	CONSTRAINT "recognitions_output_tokens_check" CHECK("output_tokens" >= 0),
	CONSTRAINT "recognitions_latency_check" CHECK("latency_ms" >= 0)
);
--> statement-breakpoint
INSERT INTO `__new_recognitions`("id", "account_id", "photo_hash", "input_fingerprint", "prompt_version", "model", "result_json", "raw_model_json", "provider_request_id", "input_tokens", "output_tokens", "latency_ms", "created_at") SELECT "id", "account_id", "photo_hash", "input_fingerprint", "prompt_version", "model", "result_json", "raw_model_json", "provider_request_id", "input_tokens", "output_tokens", "latency_ms", "created_at" FROM `recognitions`;--> statement-breakpoint
DROP TABLE `recognitions`;--> statement-breakpoint
ALTER TABLE `__new_recognitions` RENAME TO `recognitions`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `recognitions_cache_idx` ON `recognitions` (`account_id`,`input_fingerprint`,`prompt_version`,`model`);--> statement-breakpoint
CREATE INDEX `recognitions_account_created_idx` ON `recognitions` (`account_id`,`created_at`);
