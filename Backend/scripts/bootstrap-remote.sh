#!/usr/bin/env bash
# One-time setup of the production Worker: database, secrets, schema, deploy.
#
# Everything after authentication is scripted, so the state of the deployment is
# something you can read here rather than something that happened once in a
# terminal a month ago.
#
#   export CLOUDFLARE_API_TOKEN=…      # Workers Scripts, D1 and R2: Edit; Account: Read
#   ./scripts/bootstrap-remote.sh
#
# Or `pnpm wrangler login` first and skip the token.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! pnpm wrangler whoami >/dev/null 2>&1; then
  echo "error: wrangler has no credentials."
  echo "  export CLOUDFLARE_API_TOKEN=… (Workers Scripts, D1 and R2: Edit; Account Settings: Read)"
  echo "  or run: pnpm wrangler login"
  exit 1
fi

echo "==> R2"
if pnpm wrangler r2 bucket list 2>/dev/null | grep -q '"name": "eatsome-media"'; then
  echo "    eatsome-media already exists"
else
  pnpm wrangler r2 bucket create eatsome-media
fi

if grep -q "local-development-replace-before-deploy" wrangler.jsonc; then
  echo "==> Creating the D1 database"
  # APAC because that is where the phone is; D1 reads are single-region and the
  # round trip is the whole latency budget for a sync.
  # Only an existing database is a tolerable failure. Swallowing everything
  # turned a permissions or network error into "now paste the id it printed",
  # and it printed nothing.
  if ! output=$(pnpm wrangler d1 create eatsome --location=apac 2>&1); then
    if grep -qi "already exists" <<<"$output"; then
      echo "    database already exists; run: pnpm wrangler d1 list"
    else
      echo "$output"
      echo
      echo "error: could not create the database. Nothing else has been changed."
      exit 1
    fi
  else
    echo "$output"
  fi
  echo
  echo "Copy the printed database_id into wrangler.jsonc, then run this again."
  exit 0
fi

echo "==> Secrets"
# Provider credentials stay on the Worker. The app authenticates with its
# account session and never embeds a backend secret.
for secret in OPENAI_API_KEY GEMINI_API_KEY ANTHROPIC_API_KEY QWEN_API_KEY; do
  if pnpm wrangler secret list 2>/dev/null | grep -q "\"$secret\""; then
    echo "    $secret already set"
  else
    echo "    $secret — paste it at the prompt (input is hidden)"
    pnpm wrangler secret put "$secret"
  fi
done

echo "==> Schema"
pnpm db:migrate:remote

echo "==> Deploy"
pnpm deploy

# Deploy the session-only Worker before deleting the old binding. Reversing
# this order would break the currently deployed version between the two steps.
if pnpm wrangler secret list 2>/dev/null | grep -q '"EATSOME_API_TOKEN"'; then
  echo "==> Retire legacy app token"
  pnpm wrangler secret delete EATSOME_API_TOKEN
fi

echo
echo "Check it answered:"
echo "  curl -s https://eatsome-api.<your-subdomain>.workers.dev/api/health | jq"
echo
echo "That endpoint reports every provider and which of them is missing a key,"
echo "so a misconfigured deployment says so before a photo does."
