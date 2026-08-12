# Food taxonomy transition

Version 20 replaces the retired diet-oriented `group` field with the
composition-oriented `kind`, plus preparation and composition facets.

## Rollout

1. Deploy the v20 Worker and app with the decoder bridge still present.
2. Authorize Wrangler for the Cloudflare account that owns `eatsome`, then run
   `node scripts/migrate-food-taxonomy.mjs --audit` from `Backend`. Record the
   tester account's event and meal counts.
3. Run the migration with a new backup path:
   `node scripts/migrate-food-taxonomy.mjs --apply
   --backup=../backups/eatsome-before-food-kind.sql`.
   It exports D1 before writing and verifies that no canonical legacy rows
   remain. Raw model responses are preserved unchanged as evidence.
4. On the tester's existing install, wait for event upload to finish. Confirm
   the server count is at least the local event count and that recent meals and
   edits are present.
5. Reinstall, sign in with the same Apple account, and let history sync. Compare
   event/meal counts and spot-check old corrections. The app now downloads any
   locally missing meal photos by their event hashes; spot-check those too.
   Photos that never reached private R2 cannot be reconstructed by reinstall.
6. Only after that audit passes, remove code marked
   `TAXONOMY_BRIDGE_REMOVE_AFTER_V20_AUDIT` and the legacy `group` branches in
   the Worker stored-data schema. Run the audit again; it must report zero
   legacy canonical rows before deploying the bridge-free release.

Reinstalling alone does not migrate data. It is useful as the final proof that
D1 is complete and the new client can reconstruct the account from server
history. Sign in with Apple is required again because an uninstall clears the
local account pairing even when an old Keychain credential survives.
