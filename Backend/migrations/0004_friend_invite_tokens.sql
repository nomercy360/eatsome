-- Development access without a login screen. The raw bearer token is shown
-- once to the invited person; only its SHA-256 digest is retained here.
CREATE TABLE friend_invite_tokens (
  token_hash TEXT PRIMARY KEY NOT NULL,
  account_id TEXT NOT NULL,
  label TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  CONSTRAINT friend_invite_tokens_hash_check CHECK(length(token_hash) = 64)
);
CREATE INDEX friend_invite_tokens_account_idx
  ON friend_invite_tokens (account_id, revoked_at);
CREATE INDEX friend_invite_tokens_label_idx
  ON friend_invite_tokens (label, revoked_at);
