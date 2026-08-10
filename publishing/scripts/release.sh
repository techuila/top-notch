#!/usr/bin/env bash
# Builds, signs, notarizes and staples a distributable TopNotch DMG.
#
# This project has no .xcodeproj on purpose, so the usual `xcodebuild archive` path does
# not apply. The bundle is assembled by Scripts/bundle.sh and signed by hand here with a
# real identity, hardened runtime and a secure timestamp, which is everything the notary
# service checks for.
#
# One-time setup, in this order:
#   1. Create a "Developer ID Application" certificate at
#      https://developer.apple.com/account/resources/certificates/add
#      and double-click the .cer so it lands in the login keychain.
#   2. Store notary credentials (uses an app-specific password from appleid.apple.com):
#      xcrun notarytool store-credentials topnotch \
#        --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD
#
# Then: ./publishing/scripts/release.sh "Developer ID Application: Your Name (TEAMID)"
set -euo pipefail

IDENTITY="${1:?usage: release.sh \"Developer ID Application: Name (TEAMID)\" [notary-profile]}"
PROFILE="${2:-topnotch}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/build/TopNotch.app"
OUT="$ROOT/build/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

case "$IDENTITY" in
  "Developer ID Application"*) ;;
  *) echo "error: identity must be a Developer ID Application certificate, got: $IDENTITY" >&2
     echo "       (Apple Development and iPhone Distribution certificates cannot notarize)" >&2
     exit 1 ;;
esac

"$ROOT/Scripts/bundle.sh" release

rm -rf "$OUT"
mkdir -p "$OUT"

# Innermost first, so every outer seal covers a finished inner one. The adapter pieces
# get the hardened runtime but no entitlements; only the app itself needs Apple Events.
if [ -d "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
fi

codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/Resources/TopNotch.entitlements" \
  --sign "$IDENTITY" "$APP"

# The same two checks the notary service runs first.
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" \
  || { echo "error: not signed with Developer ID" >&2; exit 1; }

DMG="$OUT/TopNotch-$VERSION.dmg"
STAGE="$OUT/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "TopNotch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# The DMG carries its own signature; without it the spctl assessment below rejects the
# image with "no usable signature" even when the app inside is notarized.
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "submitting $DMG for notarization..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

# Prove the whole chain from a cold Gatekeeper's point of view.
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo
echo "done: $DMG"
echo "This is the file to attach to the GitHub release."
