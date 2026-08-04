#!/usr/bin/env bash
# One command from a fresh clone to an openable workspace.
set -euo pipefail

# CocoaPods aborts on a non-UTF-8 locale, which is the default in a plain shell.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: Xcode is not installed or not selected."
  echo
  echo "  1. Install Xcode from the App Store."
  echo "  2. sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo "  3. xcodebuild -runFirstLaunch"
  echo
  exit 1
fi

command -v xcodegen >/dev/null || { echo "error: brew install xcodegen"; exit 1; }
command -v pod >/dev/null || { echo "error: brew install cocoapods"; exit 1; }

if [ ! -f App/Resources/pose_landmarker_lite.task ]; then
  ./scripts/fetch_model.sh lite
fi

echo "Generating Shaman.xcodeproj…"
xcodegen generate

echo "Installing pods…"
pod install

echo
echo "Done. Open Shaman.xcworkspace — not the .xcodeproj."
echo "Then add your OpenAI key in Settings; it is stored in the Keychain."
