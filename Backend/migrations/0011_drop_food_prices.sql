-- `food_prices` existed only to let the legacy ingest endpoint convert a v20
-- meal without a model call. Both devices upgraded through a reinstall, which
-- wipes the local log, so there was nothing left holding a v20 line and the
-- endpoint never ran. It goes, and so does the table.
--
-- The prices themselves are not lost: they are on the meals the migration
-- wrote, which is where composition lives from v21 on.
DROP TABLE IF EXISTS food_prices;
