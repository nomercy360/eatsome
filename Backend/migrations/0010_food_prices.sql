-- Composition for a food label, so a v20 event arriving after the bulk
-- migration can be converted without a model call inside a sync request.
--
-- Populated by scripts/migrate-v21.mjs, which prices every distinct label in
-- the log once. A late line from a device that had not synced is then almost
-- always a label already in here — it came off the same trays.
--
-- Goes with the legacy ingest endpoint, one release after v21 ships.
CREATE TABLE IF NOT EXISTS food_prices (
  label TEXT PRIMARY KEY,
  per_100g_json TEXT NOT NULL,
  priced_at INTEGER NOT NULL
);
