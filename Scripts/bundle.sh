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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/TopNotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# The focus sounds. Rendered by publishing/scripts/render-sounds.swift; the notification
# centre only plays sounds that live in the main bundle's Resources.
cp "$ROOT"/Resources/Sounds/*.aiff "$APP/Contents/Resources/"

# System-wide Now Playing. Without these three the app still runs; `probe()` returns
# false and it falls back to per-app AppleScript for Spotify and Apple Music.
ADAPTER="$ROOT/Vendor/mediaremote-adapter"
if [ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
  "$ROOT/Scripts/fetch-adapter.sh"
fi
if [ -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
  cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
  cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
  cp "$ADAPTER/build/MediaRemoteAdapterTestClient" "$APP/Contents/MacOS/"
  # Nested code is signed before the app, so the outer seal covers it.
  codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
  codesign --force --sign - "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
else
  echo "warning: adapter unavailable, app will fall back to AppleScript" >&2
fi

# Sparkle arrives prebuilt through SPM. The executable links it at @rpath, which
# resolves to Contents/Frameworks inside the bundle, so it must be embedded here.
SPARKLE="$(find "$ROOT/.build/artifacts" -type d -name "Sparkle.framework" -not -path "*dSYM*" | head -n 1)"
if [ -z "$SPARKLE" ]; then
  echo "error: Sparkle.framework not found in .build/artifacts; run swift build first" >&2
  exit 1
fi
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"

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
