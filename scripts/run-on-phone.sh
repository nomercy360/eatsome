#!/usr/bin/env bash
# Build, install and launch on a paired iPhone over Wi-Fi. No cable, no
# TestFlight, no review — seconds instead of the half hour a build takes to
# reach a phone through App Store Connect.
#
#   ./scripts/run-on-phone.sh              # build, install, launch
#   DEVICE=<udid> ./scripts/run-on-phone.sh   # with more than one phone paired
#
# Pairing is a one-time thing and needs the cable once: plug the phone in, open
# Xcode → Window → Devices and Simulators, tick "Connect via network", unplug.
# After that the phone answers over Wi-Fi whenever it is awake and on the same
# network. `xcrun devicectl list devices` is where you check.
#
# This installs a development build over whatever is on the phone, including a
# TestFlight one — same bundle id, so the meal log and photos survive, but the
# app is now signed by you and expires with the certificate rather than after
# 90 days. Reinstall from TestFlight to go back.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="build/device/Build/Products/Debug-iphoneos/eatsome.app"
BUNDLE_ID="${BUNDLE_ID:-app.shaman.tracker}"

# The token is a build setting, not something typed into the app, so a build
# without it installs fine and then fails on the first photo — exactly the
# failure release-testflight.sh refuses to ship, and for the same reason.
EATSOME_TOKEN_FILE="${EATSOME_TOKEN_FILE:-$HOME/.eatsome/api_token}"
if [[ -z "${EATSOME_API_TOKEN:-}" && -f "$EATSOME_TOKEN_FILE" ]]; then
  EATSOME_API_TOKEN="$(tr -d '[:space:]' < "$EATSOME_TOKEN_FILE")"
fi
if [[ -z "${EATSOME_API_TOKEN:-}" ]]; then
  echo "error: no backend token. Recognition would fail on the phone."
  echo "  export EATSOME_API_TOKEN=…   or write it to $EATSOME_TOKEN_FILE"
  exit 1
fi

# Picked rather than pasted: a udid changes when you replace a phone, and a
# hardcoded one fails in a way that looks like the phone is off.
if [[ -z "${DEVICE:-}" ]]; then
  devices_json="$(mktemp)"
  trap 'rm -f "$devices_json"' EXIT
  xcrun devicectl list devices --json-output "$devices_json" >/dev/null
  DEVICE="$(python3 - "$devices_json" <<'PY'
import json, sys

devices = json.load(open(sys.argv[1]))["result"]["devices"]
paired = [
    d for d in devices
    if "iPhone" in d.get("hardwareProperties", {}).get("deviceType", "")
    or "iPhone" in d.get("deviceProperties", {}).get("name", "")
]
if len(paired) != 1:
    names = ", ".join(
        f"{d['deviceProperties']['name']} ({d['identifier']})" for d in paired
    )
    sys.exit(f"expected one paired iPhone, found {len(paired)}: {names or 'none'}")
print(paired[0]["identifier"])
PY
)" || { echo "error: name the one you want with DEVICE=<udid>"; exit 1; }
fi

name="$(xcrun devicectl list devices | awk -v id="$DEVICE" '$0 ~ id {print $1}')"
echo "==> ${name:-device} ($DEVICE)"

echo "==> Build"
xcodebuild \
  -project eatsome.xcodeproj \
  -scheme eatsome \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath build/device \
  -allowProvisioningUpdates \
  EATSOME_API_TOKEN="$EATSOME_API_TOKEN" \
  build \
  | grep -E '^(\*\*|error:|warning: .*signing)' || true

test -d "$APP_PATH" || { echo "error: no app at $APP_PATH"; exit 1; }

echo "==> Install"
xcrun devicectl device install app --device "$DEVICE" "$APP_PATH" >/dev/null

echo "==> Launch"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null

echo
echo "Running on ${name:-the phone}. Rebuild and re-run this to replace it."
