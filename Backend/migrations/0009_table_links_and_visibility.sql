-- Link invites expire instead of remaining usable forever. Existing codes get
-- one final 24-hour window from the table's creation timestamp; opening Invite
-- again rotates them to a fresh window.
ALTER TABLE tables ADD COLUMN invite_expires_at INTEGER NOT NULL DEFAULT 0;
UPDATE tables SET invite_expires_at = created_at + 86400000 WHERE invite_expires_at = 0;

-- Sharing is a per-member boundary. A table creator choosing what "they see"
-- must not choose the same boundary for every person who joins later.
ALTER TABLE table_members ADD COLUMN show_photos INTEGER NOT NULL DEFAULT 1;
ALTER TABLE table_members ADD COLUMN show_nutrition INTEGER NOT NULL DEFAULT 0;
ALTER TABLE table_members ADD COLUMN show_body_goals INTEGER NOT NULL DEFAULT 0;
