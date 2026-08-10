-- Accounts, the identities that resolve to them, and the device partitions they
-- have adopted. Four new tables and not one column on an existing one: the
-- merge is an INSERT here, never an UPDATE over `events`. The argument is in
-- `worker/data/accounts.ts`, and the short version is that `account_id` on a
-- stored row is a fact about where it was written and is not ours to revise.
--
-- Hand-written, like every migration since 0002. `drizzle-kit generate` diffs
-- against `migrations/meta`, which this repo stopped updating at 0001, so
-- running it here would re-emit the tables 0002–0006 already built. The DDL
-- below is drizzle's own output for the four new tables, generated into a
-- scratch directory and lifted, so the schema file and the database still agree
-- statement for statement.
CREATE TABLE `accounts` (
	`id` text PRIMARY KEY NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
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
-- `partition_id` alone is the primary key. One device belongs to one account,
-- for good: a second sign-in from the same phone under a different identity is
-- reported as a conflict rather than silently moving a history off the account
-- that already had it.
CREATE TABLE `account_partitions` (
	`partition_id` text PRIMARY KEY NOT NULL,
	`account_id` text NOT NULL,
	`linked_at` integer NOT NULL,
	FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `account_partitions_account_idx` ON `account_partitions` (`account_id`);--> statement-breakpoint
-- Only the digest of a session token is stored, so a database dump is a list of
-- hashes rather than a set of working logins.
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
