-- Tables: a small group feed of shared meals. 0007 is left for the accounts
-- milestone, which created its D1 tables in schema.ts first; this migration
-- deliberately references none of them, so the two apply in either order.

-- `creator_account` is a partition string and never travels to other members:
-- before real sign-in a partition IS a device id, and the device id is the only
-- thing separating one person's log from another's. Everything a tablemate can
-- see identifies people by `member_id` and a typed display name instead.
CREATE TABLE tables (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  creator_account TEXT NOT NULL,
  invite_code TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX tables_invite_idx ON tables (invite_code);

-- `member_id` is the per-table public identity; `account_id` is the private
-- partition the person wrote under when they joined. Checks against a caller
-- read `account_id IN (partitions)` — the same union reads everywhere else use
-- — so a membership joined anonymously keeps working after sign-in without a
-- single row moving.
CREATE TABLE table_members (
  table_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  last_read_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (table_id, account_id),
  CONSTRAINT table_members_role_check CHECK (role IN ('creator', 'member'))
);
CREATE UNIQUE INDEX table_members_member_idx ON table_members (table_id, member_id);
CREATE INDEX table_members_account_idx ON table_members (account_id);

-- One feed, two kinds of row: a `share` is a meal card copied — and redacted —
-- at the moment of the tap; a `message` is words, and a reply is a message
-- with `reply_to_post_id` set. `seq` is assigned by the server per table and is
-- the feed's one total order: no device clock is trusted to sort someone
-- else's dinner. `author_name` is denormalized on purpose — a post is an
-- utterance, and it keeps saying who said it even after they leave the table.
CREATE TABLE table_posts (
  id TEXT PRIMARY KEY NOT NULL,
  table_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  author_account TEXT NOT NULL,
  author_member_id TEXT NOT NULL,
  author_name TEXT NOT NULL,
  kind TEXT NOT NULL,
  reply_to_post_id TEXT,
  meal_id TEXT,
  dish_name TEXT,
  body TEXT,
  ingredients_json TEXT,
  photo_object_key TEXT,
  photo_mime TEXT,
  created_at INTEGER NOT NULL,
  CONSTRAINT table_posts_kind_check CHECK (kind IN ('share', 'message')),
  CONSTRAINT table_posts_ingredients_check
    CHECK (ingredients_json IS NULL OR json_valid(ingredients_json))
);
CREATE UNIQUE INDEX table_posts_seq_idx ON table_posts (table_id, seq);
CREATE INDEX table_posts_author_idx ON table_posts (author_account);

-- Keyed by the write partition, read over the union, like everything else.
CREATE TABLE table_reactions (
  post_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, account_id, kind),
  CONSTRAINT table_reactions_kind_check CHECK (kind IN ('olive', 'heart'))
);
CREATE INDEX table_reactions_account_idx ON table_reactions (account_id);
