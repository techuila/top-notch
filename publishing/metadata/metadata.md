# TopNotch - listing metadata

Copy for the GitHub release page, a landing page, Homebrew, or any directory listing.
Written for direct distribution; see publishing/README.md for why the Mac App Store is
not an option for this app.

## Name

**TopNotch**

## Tagline (under 30 characters)

> Your notch, finally useful.

Alternatives:
- The notch that does things.
- Music, files, notes, focus. In the notch.

## Subtitle / one-liner (under 80 characters)

> Music controls, a file shelf, encrypted notes and a pomodoro, living in the MacBook notch.

## Short description (~50 words)

TopNotch turns the MacBook notch into the quietest utility on your Mac. Album art and a
live waveform sit beside the camera while music plays. Drag files onto it to stash them.
Jot encrypted notes. Run a pomodoro. When nothing is happening, it disappears completely.

## Long description

The notch is the one part of your screen nothing is allowed to use. TopNotch lives there.

While music plays, the notch grows a shoulder on each side of the camera: album art on the
left, a live waveform on the right, a progress line along the bottom edge. It reads
system-wide Now Playing, so Apple Music, Spotify, YouTube in a browser, podcasts and VLC
all get the same controls. Move the cursor close and it breathes wider; touch it and it
opens into a Liquid Glass panel with four panes:

- **Music** - transport, artwork and a scrubber for whatever is playing, from any app.
- **Drop** - a temporary shelf. Drag files at the notch and it opens to catch them; drag
  them back out one at a time or all at once. Items expire on their own.
- **Notes** - a scratchpad that encrypts every note at rest. Any note can be marked
  private, which puts it behind Touch ID. Public notes open with no prompt at all.
- **Focus** - a pomodoro. A running timer keeps a progress ring and live countdown parked
  at the far left of the notch, closed or open.

When audio stops and nothing is running, everything retracts and the notch returns to its
exact hardware dimensions. No dock icon, no window, no polling in the background - one
menu bar item holds the settings, and the app costs nothing while idle.

Everything stays on your Mac. There is no network code, no analytics and no account.

## Feature bullets (for a landing page)

- System-wide Now Playing: every player gets the same controls, not just Spotify
- Audio-reactive waveform beside the camera housing
- Drag-and-drop file shelf with automatic expiry
- Notes encrypted at rest; private notes behind Touch ID
- Pomodoro with a live countdown that never leaves the notch
- Invisible when idle; zero background cost by design
- Launch at login, on by default, one click to turn off

## Category

Utilities (`public.app-category.utilities`, already set in Info.plist)

## Keywords

notch, dynamic island, mac, macbook, now playing, music controls, file shelf, drop,
pomodoro, focus timer, quick notes, encrypted notes, menu bar, utility

## System requirements

- macOS 26 or later
- Any Mac works; a built-in notch is where it shines. On external or notchless displays
  the app draws a synthetic notch.

## URLs

| Field | Value |
|---|---|
| Website / support | https://github.com/techuila/top-notch |
| Issues | https://github.com/techuila/top-notch/issues |
| Privacy policy | publishing/metadata/privacy-policy.md (host on the repo or a page) |
| License | MIT |

## Release notes - 0.1.0

First release.

- Now Playing for every media app, with artwork, waveform and scrubbing
- Drop shelf with expiring storage
- Encrypted quick notes with per-note Touch ID
- Pomodoro with a permanent idle slot
- Menu bar item with launch at login (on by default)

## Homebrew cask (submit to homebrew/homebrew-cask once a notarized DMG is on a GitHub release)

```ruby
cask "topnotch" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHASUM_OF_DMG"

  url "https://github.com/techuila/top-notch/releases/download/v#{version}/TopNotch-#{version}.dmg"
  name "TopNotch"
  desc "Music, a file shelf, encrypted notes and a pomodoro in the MacBook notch"
  homepage "https://github.com/techuila/top-notch"

  depends_on macos: ">= :tahoe"

  app "TopNotch.app"

  zap trash: [
    "~/Library/Application Support/com.aliteo.topnotch",
    "~/Library/Caches/com.aliteo.topnotch",
    "~/Library/Preferences/com.aliteo.topnotch.plist",
  ]
end
```
