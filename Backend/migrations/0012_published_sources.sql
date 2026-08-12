-- Published figures for a branded product, cached for everyone.
--
-- Not partitioned by account, and that is deliberate rather than an oversight:
-- what a chain publishes about a Big Mac belongs to nobody, and the key is a
-- brand, a product name and a market — the same three strings for every person
-- who photographs one. Partitioning it would mean paying for the same two
-- grounded calls once per user for the most-photographed foods there are.
--
-- Nothing here is a food table. `food_prices` (0010, dropped in 0011) and the
-- composition table before it failed because a free-text label had to match a
-- key and 78% of logged grams matched nothing. A miss here costs an estimate
-- the app was going to use anyway, so the failure is bounded rather than
-- silent — and misses are cached too, in `refusal`, so an unfindable product
-- stops costing money after the first attempt.
--
-- `lookup_key` carries a version prefix. When the lookup's prompts or its
-- host checks change, the prefix changes and every old answer ages out unread,
-- for the same reason `prompt_version` namespaces `recognitions`.
CREATE TABLE IF NOT EXISTS published_sources (
  lookup_key TEXT PRIMARY KEY,
  -- {panel, sourceRef} for one serving of the product. NULL on a refusal.
  figures_json TEXT,
  -- "reason: detail" on a refusal. NULL on a hit. Exactly one of these two
  -- columns is set.
  refusal TEXT,
  looked_up_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  CONSTRAINT published_sources_json_check
    CHECK (figures_json IS NULL OR json_valid(figures_json)),
  CONSTRAINT published_sources_outcome_check
    CHECK ((figures_json IS NULL) <> (refusal IS NULL))
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS published_sources_expiry_idx ON published_sources (expires_at);
