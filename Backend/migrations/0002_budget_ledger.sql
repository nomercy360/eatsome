-- An atomic reservation, because reading a count and then spending money is a
-- race: every concurrent request can observe 399 and proceed. SQLite serialises
-- writes within a D1 database, so a conditional UPDATE that only matches while
-- the day is under its ceiling either reserves exactly one unit or reports that
-- it could not — which is the guarantee a spending cap has to make.
CREATE TABLE IF NOT EXISTS budget (
  day TEXT PRIMARY KEY,
  used INTEGER NOT NULL DEFAULT 0
);
