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

## How releases work now

Releases are automated by `.github/workflows/release-please.yml`:

1. Conventional commits land on `main`. release-please keeps a release PR open that
   accumulates a changelog and bumps `CFBundleShortVersionString` in
   `Resources/Info.plist` (via the `x-release-please-version` marker).
2. Merging that PR tags the release and creates it on GitHub.
3. The `dmg` job then builds on a macOS 26 runner, signs with Developer ID, notarizes,
   staples, and attaches `TopNotch-<version>.dmg` plus a `.sha256` file to the release.

`scripts/release.sh` still works standalone for a local release if CI is ever down.
If a release exists but its DMG build failed, fix main and run the workflow manually
(Actions, release, "Run workflow") with the release tag; it rebuilds from main and
attaches the DMG to that release.

### Repository secrets the workflow needs

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | Developer ID Application cert + key exported as .p12, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Password chosen when exporting the .p12 |
| `MACOS_SIGN_IDENTITY` | Full identity string, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | App-specific password from https://appleid.apple.com |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key that signs the Sparkle appcast (public half lives in Info.plist as `SUPublicEDKey`; a backup copy sits in the owner's keychain as "Private key for signing Sparkle updates") |

## What only you can do, in order

1. **Create a Developer ID Application certificate.** Your keychain has an Apple
   Development and an iPhone Distribution identity; neither can notarize. Go to
   https://developer.apple.com/account/resources/certificates/add, choose
   "Developer ID Application", follow the CSR steps, download and double-click the cert.
   (The App Store Connect API cannot create this certificate type; it is browser-only.)
2. **Export it as a .p12 and set the six repository secrets** in the table above
   (GitHub repo, Settings, Secrets and variables, Actions).
3. **Merge the release PR** that release-please opens. CI does the rest and attaches
   the DMG.
4. **Take the remaining screenshots** per `screenshots/SCREENSHOTS.md`.
5. Optional: **submit the Homebrew cask** from `metadata/metadata.md` (fill in the
   `shasum -a 256` that CI attached next to the DMG).

## Worth doing before 1.0, not blocking 0.1.0

- A landing page (the privacy policy needs a public URL for the Homebrew audit anyway;
  the raw GitHub file works meanwhile).
- Test the notarized build on a second Mac with a clean Gatekeeper: first launch must
  show the normal "downloaded from the internet" dialog, not a block.
