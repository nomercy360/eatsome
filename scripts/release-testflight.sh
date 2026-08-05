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

ARCHIVE="build/eatsome.xcarchive"
EXPORT_DIR="build"
IPA="$EXPORT_DIR/eatsome.ipa"

# Passed to xcodebuild so it can create the distribution certificate and profile
# without an Apple ID in Xcode's Accounts pane. Empty is fine when you signed in
# there instead.
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-none}.p8}"
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
  echo "Uploaded build $BUILD_NUMBER. Processing takes a few minutes, then it"
  echo "appears in TestFlight → iOS builds. Internal testers get it with no review."
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
