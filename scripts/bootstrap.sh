#!/usr/bin/env bash
# One command from a fresh clone to an openable Xcode project.
set -euo pipefail

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

echo "Generating eatsome.xcodeproj…"
xcodegen generate

echo
echo "Done. Open eatsome.xcodeproj."
echo "Sign in with Apple on first launch; the session it mints is the only credential."
