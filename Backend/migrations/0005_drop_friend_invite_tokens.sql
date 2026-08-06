-- Per-friend invite tokens are gone. Testers get the build, and the build
-- carries the shared app token; `X-Device-Id` is what keeps one tester's D1
-- rows, R2 objects and daily quota apart from another's.
DROP INDEX IF EXISTS friend_invite_tokens_label_idx;
DROP INDEX IF EXISTS friend_invite_tokens_account_idx;
DROP TABLE IF EXISTS friend_invite_tokens;
