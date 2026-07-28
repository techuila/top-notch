#!/usr/bin/env bash
# Builds TopNotch.app from the SPM executable.
#
# The project deliberately has no .xcodeproj. A generated pbxproj is unmergeable, and
# several agents work on this repo in parallel. SPM plus this script gives the same
# result with plain text everywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/TopNotch.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TopNotch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TopNotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature is enough to run locally. Distribution signing lives elsewhere.
codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/TopNotch.entitlements" \
  "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "built $APP"
