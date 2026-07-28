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
#
# This must NOT fall back to signing without entitlements. A malformed entitlements
# file makes AMFI reject the plist, and a silent fallback produces an app that looks
# signed, then gets refused by launchd with no useful error. Fail loudly instead.
codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/TopNotch.entitlements" \
  "$APP"

# Prove the entitlements actually landed rather than trusting the exit code.
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "apple-events"; then
  echo "error: entitlements did not apply to $APP" >&2
  exit 1
fi

echo "built $APP"
