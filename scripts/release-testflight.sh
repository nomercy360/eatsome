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
#   export ASC_KEY_ID=XXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Both tools find the file by key id in that directory, so the key itself never
# appears on a command line. Apple lets you download a .p8 exactly once.
#
# Without a key, skip --upload and drag build/eatsome.ipa into Transporter.app,
# which uses the Apple ID you are already signed into.
set -euo pipefail

cd "$(dirname "$0")/.."

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# Monotonic and reproducible: the same commit always produces the same build
# number. Override when you need to re-upload one commit twice, because App
# Store Connect rejects a build number it has already seen.
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

ARCHIVE="build/eatsome.xcarchive"
EXPORT_DIR="build"
IPA="$EXPORT_DIR/eatsome.ipa"

# Passed to xcodebuild so it can create the distribution certificate and profile
# without an Apple ID in Xcode's Accounts pane. Empty is fine when you signed in
# there instead.
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-none}.p8}"
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "$ASC_KEY_PATH" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

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
  -allowProvisioningUpdates "${AUTH[@]}" \
  | grep -E '^(\*\*|error:|warning: .*(deprecat|signing))' || true

test -d "$ARCHIVE" || { echo "error: no archive produced"; exit 1; }

echo "==> Export"
rm -f "$IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates "${AUTH[@]}" \
  | grep -E '^(\*\*|error:)' || true

if [[ ! -f "$IPA" ]]; then
  echo
  echo "error: no .ipa produced."
  echo "  'No Accounts' / 'No profiles for app.shaman.tracker' means signing has"
  echo "  no credentials: sign in at Xcode → Settings → Accounts, or export"
  echo "  ASC_KEY_ID and ASC_ISSUER_ID for an Admin App Store Connect API key."
  exit 1
fi
echo "    $IPA"

if [[ "$UPLOAD" == false ]]; then
  echo
  echo "Not uploaded. Either re-run with --upload, or drag $IPA into Transporter.app."
  exit 0
fi

: "${ASC_KEY_ID:?set ASC_KEY_ID and ASC_ISSUER_ID (see the header)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

echo "==> Upload"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded build $BUILD_NUMBER. Processing takes a few minutes, then it"
echo "appears in TestFlight → iOS builds. Internal testers get it with no review."
