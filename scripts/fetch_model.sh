#!/usr/bin/env bash
# Downloads the MediaPipe pose model into the app bundle sources.
# The model is ~5MB of Google's weights, so it is fetched rather than committed.
set -euo pipefail

VARIANT="${1:-lite}"   # lite | full | heavy
DEST="$(cd "$(dirname "$0")/.." && pwd)/App/Resources"
NAME="pose_landmarker_${VARIANT}"
URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/${NAME}/float16/latest/${NAME}.task"

mkdir -p "$DEST"
echo "Fetching ${NAME}.task…"
curl -fL --progress-bar "$URL" -o "$DEST/${NAME}.task"

echo "→ $DEST/${NAME}.task ($(du -h "$DEST/${NAME}.task" | cut -f1))"
if [ "$VARIANT" != "lite" ]; then
  echo "Note: MediaPipePoseProvider defaults to 'pose_landmarker_lite'."
  echo "Pass the name to its initialiser to use this one."
fi
