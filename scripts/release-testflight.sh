#!/usr/bin/env bash
# Release build → signed .ipa → TestFlight. The way to update the app on a
# phone that is not on this network.
#
#   ./scripts/release-testflight.sh            # archive and export only
#   ./scripts/release-testflight.sh --upload   # …and send it to App Store Connect
#
# Signing a distribution build needs a developer account. Either sign in once in
# Xcode → Settings → Accounts, or — better for a script — create an App Store
# Connect API key with the Admin role under Users and Access → Integrations:
#
#   mkdir -p ~/.appstoreconnect/private_keys
#   mv ~/Downloads/AuthKey_XXXXXXXX.p8 ~/.appstoreconnect/private_keys/
#   echo xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx > ~/.appstoreconnect/issuer_id
#
# The key id is read back from the AuthKey_*.p8 filename, so only the issuer id
# has to be recorded. Both can still be overridden with ASC_KEY_ID and
# ASC_ISSUER_ID. The issuer id is also what lets this script hand the finished
# build to your internal testers — without it the upload succeeds and nobody
# receives anything.
#
# The key is referenced by path, never pasted onto a command line. Apple lets
# you download a .p8 exactly once.
#
# Without a key, skip --upload and drag build/eatsome.ipa into Transporter.app,
# which uses the Apple ID you are already signed into.
#
# Uploads must be built with Xcode 26 or later against the iOS 26 SDK as of
# 28 April 2026, which is what this produces.
set -euo pipefail

cd "$(dirname "$0")/.."

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# Monotonic and reproducible: the same commit always produces the same build
# number. Override when you need to re-upload one commit twice, because App
# Store Connect rejects a build number it has already seen.
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

# Also the id in ExportOptions-upload.plist and the App Store Connect record.
BUNDLE_ID="${BUNDLE_ID:-app.shaman.tracker}"
ARCHIVE="build/eatsome.xcarchive"
EXPORT_DIR="build"
IPA="$EXPORT_DIR/eatsome.ipa"

# Passed to xcodebuild so it can create the distribution certificate and profile
# without an Apple ID in Xcode's Accounts pane. Empty is fine when you signed in
# there instead.
# Resolve the App Store Connect credentials before anything needs them.
#
# Both halves used to be required as environment variables and neither was
# discoverable, so a clean shell silently fell back to Xcode's account plumbing
# and the upload worked while the assignment step had no way to authenticate.
# The key id is recoverable from the filename Apple ships; the issuer id is not
# recoverable from anything on disk, so it is read from a file you write once.
ASC_KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
if [[ -z "${ASC_KEY_ID:-}" ]]; then
  # Exactly one key is the normal case; with several, name the one you want.
  found=("$ASC_KEY_DIR"/AuthKey_*.p8)
  if [[ ${#found[@]} -eq 1 && -f "${found[0]}" ]]; then
    ASC_KEY_ID="$(basename "${found[0]}" .p8)"
    ASC_KEY_ID="${ASC_KEY_ID#AuthKey_}"
  fi
fi
# `ant`-style config file so this survives a new shell: one line, the issuer
# UUID from App Store Connect → Users and Access → Integrations.
ASC_ISSUER_FILE="${ASC_ISSUER_FILE:-$HOME/.appstoreconnect/issuer_id}"
if [[ -z "${ASC_ISSUER_ID:-}" && -f "$ASC_ISSUER_FILE" ]]; then
  ASC_ISSUER_ID="$(tr -d '[:space:]' < "$ASC_ISSUER_FILE")"
fi
ASC_KEY_PATH="${ASC_KEY_PATH:-$ASC_KEY_DIR/AuthKey_${ASC_KEY_ID:-none}.p8}"
# Empty by default, and `set -u` treats an empty array as unset before bash 4.4,
# so it is seeded with a harmless flag rather than left bare.
AUTH=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "$ASC_KEY_PATH" ]]; then
  # Appended, never replacing: the key says who you are, and
  # -allowProvisioningUpdates is what lets xcodebuild act on it and create the
  # distribution certificate and profile that do not exist yet.
  AUTH+=(-authenticationKeyPath "$ASC_KEY_PATH"
         -authenticationKeyID "$ASC_KEY_ID"
         -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# The archive carries the shared Worker token, the same way it carries the
# issuer id: from a one-line file so it survives a new shell. Nobody types a
# credential into the app, so a build without this one reaches TestFlight and
# fails on the first photo — which is why it is a hard error here.
EATSOME_TOKEN_FILE="${EATSOME_TOKEN_FILE:-$HOME/.eatsome/api_token}"
if [[ -z "${EATSOME_API_TOKEN:-}" && -f "$EATSOME_TOKEN_FILE" ]]; then
  EATSOME_API_TOKEN="$(tr -d '[:space:]' < "$EATSOME_TOKEN_FILE")"
fi
if [[ -z "${EATSOME_API_TOKEN:-}" ]]; then
  echo "error: no backend token. Recognition would fail on every tester's phone."
  echo "  export EATSOME_API_TOKEN=…   (the same value as the Worker secret)"
  echo "  or write it to $EATSOME_TOKEN_FILE"
  exit 1
fi
BACKEND_BUILD_SETTING=("EATSOME_API_TOKEN=$EATSOME_API_TOKEN")

command -v xcodegen >/dev/null || { echo "error: brew install xcodegen"; exit 1; }

echo "==> Tests"
SHAMAN_TESTING_PACKAGE=1 swift test --package-path Core >/dev/null

echo "==> Project"
xcodegen generate >/dev/null

echo "==> Archive (build $BUILD_NUMBER)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project eatsome.xcodeproj \
  -scheme eatsome \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${BACKEND_BUILD_SETTING[@]}" \
  "${AUTH[@]}" \
  | grep -E '^(\*\*|error:|warning: .*(deprecat|signing))' || true

test -d "$ARCHIVE" || { echo "error: no archive produced"; exit 1; }

signing_help() {
  cat <<'HELP'

  Two failures land here, and they mean opposite things.

  "Error Downloading App Information", logged as missingApp(bundleId:), means
  authentication worked and there is simply no app record yet. Create one at
  App Store Connect → Apps → +, picking the existing bundle id
  app.shaman.tracker. The app name has to be unique across the whole App Store;
  everything else can be changed later.

  "No Accounts" / "No profiles for app.shaman.tracker" is the opposite: signing
  found no credentials with App Store Connect access. Note these are separate
  systems — an Apple ID can hold Certificates, Identifiers & Profiles in the
  developer portal and still have no App Store Connect access at all, and a
  membership that lapsed leaves Xcode holding a token that looks fine until you
  try to distribute. Re-add the account in Xcode → Settings → Apple Accounts, or
  export ASC_KEY_ID and ASC_ISSUER_ID for an Admin API key, which skips Xcode's
  account plumbing entirely.

  The full story is always in the last log under
  /var/folders/**/T/eatsome_*.xcdistributionlogs/IDEDistribution.verbose.log
HELP
}

if [[ "$UPLOAD" == true ]]; then
  # `destination: upload` runs Xcode's own upload pipeline — the Organizer
  # button, essentially — instead of altool, whose Xcode 26 build can target the
  # wrong app when bundle ids share a prefix and call the failure a success.
  echo "==> Export and upload"
  if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist scripts/ExportOptions-upload.plist \
    "${AUTH[@]}"; then
    signing_help
    exit 1
  fi

  echo
  echo "Uploaded build $BUILD_NUMBER."

  # Uploading is not distributing. Unless the group has "Automatically
  # distribute new builds" switched on, a processed build reaches nobody until
  # it is attached to one — which is how build 35 sat VALID and unseen while
  # this script reported success.
  echo "==> Assign to internal testers"
  if [[ -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_ID:-}" ]]; then
    echo "    skipped: need ASC_KEY_ID and ASC_ISSUER_ID to reach the API."
    echo "    Write the issuer UUID to $ASC_ISSUER_FILE, then re-run:"
    echo "      ./scripts/testflight-assign.py $BUNDLE_ID $BUILD_NUMBER"
  else
    export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH
    set +e
    python3 scripts/testflight-assign.py "$BUNDLE_ID" "$BUILD_NUMBER"
    assign_status=$?
    set -e
    if [[ $assign_status -eq 2 ]]; then
      echo "    skipped: assignment needs PyJWT. The build uploaded fine; finish with"
      echo "      pip3 install --user pyjwt cryptography"
      echo "      ./scripts/testflight-assign.py $BUNDLE_ID $BUILD_NUMBER"
    elif [[ $assign_status -ne 0 ]]; then
      echo "    the build uploaded; only the assignment failed. Re-run:"
      echo "      ./scripts/testflight-assign.py $BUNDLE_ID $BUILD_NUMBER"
      exit 1
    fi
  fi
  exit 0
fi

echo "==> Export"
rm -f "$IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  "${AUTH[@]}" \
  | grep -E '^(\*\*|error:)' || true

if [[ ! -f "$IPA" ]]; then
  echo "error: no .ipa produced."
  signing_help
  exit 1
fi

echo "    $IPA"
echo
echo "Not uploaded. Either re-run with --upload, or drag $IPA into Transporter.app."
