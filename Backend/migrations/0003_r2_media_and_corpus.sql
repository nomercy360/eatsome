-- The note is part of the model input. Existing development rows had no note,
-- so their photo hash is the correct initial fingerprint.
ALTER TABLE recognitions ADD COLUMN input_fingerprint TEXT;
UPDATE recognitions SET input_fingerprint = photo_hash WHERE input_fingerprint IS NULL;
DROP INDEX recognitions_cache_idx;
CREATE UNIQUE INDEX recognitions_cache_idx
  ON recognitions (account_id, input_fingerprint, prompt_version, model);

-- Exact bytes sent to the model. `stored_at` remains null while an interrupted
-- upload is repairable; the scheduled orphan sweep removes stale pending rows.
CREATE TABLE media_objects (
  account_id TEXT NOT NULL,
  photo_hash TEXT NOT NULL,
  object_key TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  stored_at TEXT,
  PRIMARY KEY (account_id, photo_hash),
  CONSTRAINT media_objects_hash_check CHECK(length(photo_hash) = 64),
  CONSTRAINT media_objects_size_check CHECK(byte_size >= 0)
);
CREATE UNIQUE INDEX media_objects_key_idx ON media_objects (object_key);
CREATE INDEX media_objects_orphans_idx ON media_objects (created_at, stored_at);

-- A projection of the latest event for each meal. Deletions are tombstones
-- (photo_hash = NULL), which prevents an old replay from resurrecting a ref.
CREATE TABLE meal_media (
  account_id TEXT NOT NULL,
  meal_id TEXT NOT NULL,
  photo_hash TEXT,
  event_id TEXT NOT NULL,
  recorded_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, meal_id)
);
CREATE INDEX meal_media_reference_idx ON meal_media (account_id, photo_hash);

-- A crop has different bytes from the model input and therefore a different
-- content hash. Multiple consent/provenance rows may reference one deduped crop.
CREATE TABLE corpus_objects (
  corpus_hash TEXT PRIMARY KEY NOT NULL,
  object_key TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  stored_at TEXT,
  CONSTRAINT corpus_objects_hash_check CHECK(length(corpus_hash) = 64),
  CONSTRAINT corpus_objects_size_check CHECK(byte_size >= 0)
);
CREATE UNIQUE INDEX corpus_objects_key_idx ON corpus_objects (object_key);
CREATE INDEX corpus_objects_orphans_idx ON corpus_objects (created_at, stored_at);

CREATE TABLE corpus_items (
  source_user TEXT NOT NULL,
  meal_id TEXT NOT NULL,
  source_photo_hash TEXT NOT NULL,
  corpus_hash TEXT NOT NULL,
  consent_policy_version TEXT NOT NULL,
  consent_captured_at INTEGER NOT NULL,
  crop_method TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (source_user, meal_id),
  CONSTRAINT corpus_items_source_hash_check CHECK(length(source_photo_hash) = 64),
  CONSTRAINT corpus_items_corpus_hash_check CHECK(length(corpus_hash) = 64)
);
CREATE INDEX corpus_items_user_idx ON corpus_items (source_user);
CREATE INDEX corpus_items_object_idx ON corpus_items (corpus_hash);

CREATE TABLE corpus_consents (
  account_id TEXT PRIMARY KEY NOT NULL,
  enabled INTEGER NOT NULL,
  policy_version TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
