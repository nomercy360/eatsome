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
CREATE TABLE `meal_evals` (
	`event_id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`device_id` text NOT NULL,
	`meal_id` text NOT NULL,
	`photo_hash` text NOT NULL,
	`prompt_version` text NOT NULL,
	`raw_model_json` text NOT NULL,
	`initial_items_json` text NOT NULL,
	`final_items_json` text NOT NULL,
	`other_meals_visible` integer NOT NULL,
	`was_corrected` integer NOT NULL,
	`recorded_at` integer NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "meal_evals_initial_json_check" CHECK(json_valid("meal_evals"."initial_items_json")),
	CONSTRAINT "meal_evals_final_json_check" CHECK(json_valid("meal_evals"."final_items_json")),
	CONSTRAINT "meal_evals_hash_check" CHECK(length("meal_evals"."photo_hash") = 64)
);
--> statement-breakpoint
CREATE INDEX `meal_evals_account_created_idx` ON `meal_evals` (`account_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `meal_evals_prompt_idx` ON `meal_evals` (`prompt_version`,`created_at`);--> statement-breakpoint
CREATE INDEX `meal_evals_meal_idx` ON `meal_evals` (`meal_id`,`recorded_at`);--> statement-breakpoint
CREATE TABLE `recognitions` (
	`id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`photo_hash` text NOT NULL,
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
	CONSTRAINT "recognitions_hash_check" CHECK(length("recognitions"."photo_hash") = 64),
	CONSTRAINT "recognitions_input_tokens_check" CHECK("recognitions"."input_tokens" >= 0),
	CONSTRAINT "recognitions_output_tokens_check" CHECK("recognitions"."output_tokens" >= 0),
	CONSTRAINT "recognitions_latency_check" CHECK("recognitions"."latency_ms" >= 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `recognitions_cache_idx` ON `recognitions` (`account_id`,`photo_hash`,`prompt_version`,`model`);--> statement-breakpoint
CREATE INDEX `recognitions_account_created_idx` ON `recognitions` (`account_id`,`created_at`);