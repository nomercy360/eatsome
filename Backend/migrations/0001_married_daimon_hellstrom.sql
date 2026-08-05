PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_meal_evals` (
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
	CONSTRAINT "meal_evals_initial_json_check" CHECK(json_valid("__new_meal_evals"."initial_items_json")),
	CONSTRAINT "meal_evals_final_json_check" CHECK(json_valid("__new_meal_evals"."final_items_json")),
	CONSTRAINT "meal_evals_raw_json_check" CHECK(json_valid("__new_meal_evals"."raw_model_json")),
	CONSTRAINT "meal_evals_hash_check" CHECK(length("__new_meal_evals"."photo_hash") = 64)
);
--> statement-breakpoint
INSERT INTO `__new_meal_evals`("event_id", "account_id", "device_id", "meal_id", "photo_hash", "prompt_version", "raw_model_json", "initial_items_json", "final_items_json", "other_meals_visible", "was_corrected", "recorded_at", "created_at") SELECT "event_id", "account_id", "device_id", "meal_id", "photo_hash", "prompt_version", "raw_model_json", "initial_items_json", "final_items_json", "other_meals_visible", "was_corrected", "recorded_at", "created_at" FROM `meal_evals`;--> statement-breakpoint
DROP TABLE `meal_evals`;--> statement-breakpoint
ALTER TABLE `__new_meal_evals` RENAME TO `meal_evals`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `meal_evals_account_created_idx` ON `meal_evals` (`account_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `meal_evals_prompt_idx` ON `meal_evals` (`prompt_version`,`created_at`);--> statement-breakpoint
CREATE INDEX `meal_evals_meal_idx` ON `meal_evals` (`meal_id`,`recorded_at`);--> statement-breakpoint
CREATE TABLE `__new_recognitions` (
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
	CONSTRAINT "recognitions_result_json_check" CHECK(json_valid("__new_recognitions"."result_json")),
	CONSTRAINT "recognitions_raw_json_check" CHECK(json_valid("__new_recognitions"."raw_model_json")),
	CONSTRAINT "recognitions_hash_check" CHECK(length("__new_recognitions"."photo_hash") = 64),
	CONSTRAINT "recognitions_input_tokens_check" CHECK("__new_recognitions"."input_tokens" >= 0),
	CONSTRAINT "recognitions_output_tokens_check" CHECK("__new_recognitions"."output_tokens" >= 0),
	CONSTRAINT "recognitions_latency_check" CHECK("__new_recognitions"."latency_ms" >= 0)
);
--> statement-breakpoint
INSERT INTO `__new_recognitions`("id", "account_id", "photo_hash", "prompt_version", "model", "result_json", "raw_model_json", "provider_request_id", "input_tokens", "output_tokens", "latency_ms", "created_at") SELECT "id", "account_id", "photo_hash", "prompt_version", "model", "result_json", "raw_model_json", "provider_request_id", "input_tokens", "output_tokens", "latency_ms", "created_at" FROM `recognitions`;--> statement-breakpoint
DROP TABLE `recognitions`;--> statement-breakpoint
ALTER TABLE `__new_recognitions` RENAME TO `recognitions`;--> statement-breakpoint
CREATE UNIQUE INDEX `recognitions_cache_idx` ON `recognitions` (`account_id`,`photo_hash`,`prompt_version`,`model`);--> statement-breakpoint
CREATE INDEX `recognitions_account_created_idx` ON `recognitions` (`account_id`,`created_at`);