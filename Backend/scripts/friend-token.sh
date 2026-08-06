#!/usr/bin/env bash
# Issue, rotate, list, or revoke development invite tokens in the remote D1.
# Raw tokens are printed once and never written to the database or this repo.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'HELP'
Usage:
  ./scripts/friend-token.sh issue "Friend label" [existing-account-id]
  ./scripts/friend-token.sh list
  ./scripts/friend-token.sh revoke account-id

Pass an existing account id to `issue` to rotate a token without changing the
friend's R2/D1 ownership. Revocation disables every token for that account but
does not delete their data.
HELP
}

command_name="${1:-}"
wrangler=./node_modules/.bin/wrangler
[[ -x "$wrangler" ]] || { echo "error: run pnpm install in Backend"; exit 1; }

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

case "$command_name" in
  issue)
    label="${2:-}"
    [[ -n "$label" ]] || { usage; exit 1; }
    account_id="${3:-friend:$(uuidgen | tr '[:upper:]' '[:lower:]')}"
    [[ "$account_id" =~ ^friend:[A-Za-z0-9-]{8,80}$ ]] || {
      echo "error: account id must start with friend: and contain only letters, numbers, or hyphens"
      exit 1
    }
    token="eat_dev_$(openssl rand -hex 32)"
    token_hash="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
    created_at="$(date +%s)000"
    escaped_label="$(sql_escape "$label")"
    "$wrangler" d1 execute eatsome --remote --command \
      "INSERT INTO friend_invite_tokens (token_hash, account_id, label, created_at) VALUES ('$token_hash', '$account_id', '$escaped_label', $created_at);" \
      >/dev/null
    printf 'Account: %s\nLabel:   %s\nToken:   %s\n\n' "$account_id" "$label" "$token"
    echo "Copy the token now. It cannot be recovered from D1."
    ;;
  list)
    "$wrangler" d1 execute eatsome --remote --command \
      "SELECT account_id, label, created_at, revoked_at FROM friend_invite_tokens ORDER BY created_at;"
    ;;
  revoke)
    account_id="${2:-}"
    [[ "$account_id" =~ ^friend:[A-Za-z0-9-]{8,80}$ ]] || { usage; exit 1; }
    revoked_at="$(date +%s)000"
    "$wrangler" d1 execute eatsome --remote --command \
      "UPDATE friend_invite_tokens SET revoked_at = $revoked_at WHERE account_id = '$account_id' AND revoked_at IS NULL;"
    ;;
  *)
    usage
    exit 1
    ;;
esac
