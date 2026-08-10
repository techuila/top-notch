# Publishing TopNotch

Everything needed to ship TopNotch, in one folder. Status as of 2026-07-30.

## The distribution decision

**The Mac App Store is not an option for this app.** Two locked design decisions rule it
out, permanently:

1. It is not sandboxed (`DECISIONS.md`: the drop shelf needs arbitrary file access, Apple
   Events playback control). The App Store requires the sandbox, no exceptions.
2. It talks to MediaRemote, a private framework, through the vendored adapter. App Review
   scans for exactly this.

So the path is **Developer ID + notarization + direct download** (GitHub release, then
optionally Homebrew). Nothing App Store Connect hosts applies: there is no listing to
fill in, no review, no screenshots portal. The metadata in this folder is for the GitHub
release page, a landing page and the Homebrew cask instead.

## What is ready

| Item | Where | State |
|---|---|---|
| App icon | `icon/AppIcon.icns`, wired into `Resources/` + `Info.plist` + `bundle.sh` | Done |
| Icon source | `scripts/render-icon.swift` (regenerates the PNG deterministically) | Done |
| Listing copy | `metadata/metadata.md` (name, taglines, descriptions, keywords, release notes, Homebrew cask) | Done |
| Privacy policy | `metadata/privacy-policy.md` | Done |
| Release pipeline | `scripts/release.sh` (build, sign, notarize, staple, DMG) | Done, blocked on your certificate |
| Screenshot | `screenshots/01-idle-music.png` | Done |
| Remaining screenshots | `screenshots/SCREENSHOTS.md` shot list | Needs your hand |
| App category + icon keys | `Resources/Info.plist` | Done |

## What only you can do, in order

1. **Create a Developer ID Application certificate.** Your keychain has an Apple
   Development and an iPhone Distribution identity; neither can notarize. Go to
   https://developer.apple.com/account/resources/certificates/add, choose
   "Developer ID Application", follow the CSR steps, download and double-click the cert.
   (The App Store Connect API cannot create this certificate type; it is browser-only.)
2. **Store notary credentials** (needs an app-specific password from
   https://appleid.apple.com):
   ```bash
   xcrun notarytool store-credentials topnotch \
     --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD
   ```
3. **Run the release:**
   ```bash
   ./publishing/scripts/release.sh "Developer ID Application: Your Name (TEAMID)"
   ```
   Produces `build/release/TopNotch-0.1.0.dmg`, notarized and stapled.
4. **Take the remaining screenshots** per `screenshots/SCREENSHOTS.md`.
5. **Publish the GitHub release:** tag `v0.1.0`, attach the DMG, paste the release notes
   from `metadata/metadata.md`.
6. Optional: **submit the Homebrew cask** from `metadata/metadata.md` (fill in the DMG's
   `shasum -a 256` first).

## Worth doing before 1.0, not blocking 0.1.0

- A landing page (the privacy policy needs a public URL for the Homebrew audit anyway;
  the raw GitHub file works meanwhile).
- Sparkle or similar for in-app updates; direct-download apps get no update channel for
  free.
- Test the notarized build on a second Mac with a clean Gatekeeper: first launch must
  show the normal "downloaded from the internet" dialog, not a block.
