#!/usr/bin/env bash
# Fetches and builds mediaremote-adapter into Vendor/.
#
# Why this exists: Apple restricted MediaRemote around macOS 15.4, so an unentitled app
# gets a NIL payload back. This adapter runs the framework from Apple-signed /usr/bin/perl,
# which inherits the entitlement, and streams the result back. Verified working on 26.5
# where raw MediaRemote returns nothing. See docs/research/nowplaying.md.
#
# Nothing is committed. Vendor/ is gitignored, the pin below is the only thing tracked.
#
# BSD 3-Clause, Jonas van den Berg and contributors.
set -euo pipefail

REPO="https://github.com/ungive/mediaremote-adapter.git"
# Pinned deliberately. Do not float this; the adapter reaches into a private framework
# and an unreviewed upstream change is not something to pick up silently.
PIN="3ac3d4bdf862c7b5399b4fba4df5689f5c38609a"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor/mediaremote-adapter"

if [ -d "$VENDOR/.git" ] && [ "$(git -C "$VENDOR" rev-parse HEAD)" = "$PIN" ] \
   && [ -d "$VENDOR/build/MediaRemoteAdapter.framework" ]; then
  echo "adapter already at $PIN"
  exit 0
fi

rm -rf "$VENDOR"
mkdir -p "$(dirname "$VENDOR")"
git clone --quiet "$REPO" "$VENDOR"
git -C "$VENDOR" checkout --quiet "$PIN"

cmake -S "$VENDOR" -B "$VENDOR/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$VENDOR/build" >/dev/null

for artifact in \
  "$VENDOR/bin/mediaremote-adapter.pl" \
  "$VENDOR/build/MediaRemoteAdapter.framework" \
  "$VENDOR/build/MediaRemoteAdapterTestClient"
do
  [ -e "$artifact" ] || { echo "error: missing $artifact" >&2; exit 1; }
done

echo "adapter built at $PIN"
