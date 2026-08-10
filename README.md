# TopNotch

A macOS notch app. Now Playing, a temporary file shelf, quick notes and a pomodoro,
all living in the MacBook notch.

TopNotch has no dock icon and no window. When nothing is happening it retracts to exactly
the hardware dimensions of the notch and disappears. When music is playing it grows a
shoulder on each side of the camera housing for album art and a live waveform. Move the
cursor near it and it opens into a panel.

A single menu bar item holds the settings: open the notch, launch at login, quit. It
launches at login by default, and that can be turned off from the menu or from System
Settings under Login Items.

## Install

Download the DMG from the [latest release](https://github.com/techuila/top-notch/releases/latest),
drag TopNotch to Applications and open it. Builds are Developer ID signed and notarized,
and the app updates itself through Sparkle: it checks the latest GitHub release and offers
the new version when there is one.

## Requirements

- macOS 26 or later (the UI is built on the macOS 26 Liquid Glass material)
- A Mac with a notch, for the parts that live in the notch
- Swift 6.2 toolchain (Xcode 26 or a matching open-source toolchain)
- CMake, only if you want system-wide Now Playing (see below)

## Build

```
swift build            # compile
swift test             # notes store and pomodoro engine
./Scripts/bundle.sh    # produce build/TopNotch.app, ad-hoc signed
open build/TopNotch.app
```

There is no `.xcodeproj` on purpose. A generated `pbxproj` cannot be merged, and this repo
is worked on by several agents in parallel. `Package.swift` plus `Scripts/bundle.sh` gives
the same result with plain text everywhere.

`bundle.sh` signs ad-hoc, which is enough to run locally. It refuses to fall back to
signing without entitlements, because a silently unentitled build looks fine and then gets
refused by launchd with no useful error.

## The four panes

| Pane | What it does |
|---|---|
| **Music** | System-wide Now Playing with transport, artwork and a scrubber. Works with Apple Music, Spotify, a browser tab, podcasts, VLC. |
| **Drop** | A temporary shelf. Drag files at the notch, it opens and catches them. Drag them back out one at a time or all at once. Items expire and are purged. |
| **Notes** | Quick notes. Plain text, saved to disk as you type, no lock and no prompt. |
| **Focus** | A pomodoro. A running timer holds a permanent slot in the idle notch with a progress ring and countdown. |

## Now Playing

Reading system-wide Now Playing means the private `MediaRemote` framework, which Apple
restricted around macOS 15.4 so an unentitled app gets an empty payload back.

TopNotch handles that behind a `NowPlayingSource` protocol with two conformers:

1. **System source.** Uses [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
   (BSD 3-Clause, Jonas van den Berg and contributors), which runs the framework from
   Apple-signed `/usr/bin/perl` so it inherits the entitlement, and streams results back.
   Verified working on macOS 26.5.
2. **AppleScript fallback.** Spotify and Apple Music only, used when the adapter is not
   present or its self-test fails.

The adapter is **not vendored**. `Scripts/fetch-adapter.sh` clones and builds it into
`Vendor/`, which is gitignored; only the commit pin is tracked. The pin is deliberate and
should not float, because the adapter reaches into a private framework. `bundle.sh` runs
the fetch automatically and warns, rather than fails, if the adapter cannot be built.

The full research behind this, including what was measured on macOS 26.5 and what the
alternatives cost, is in [`docs/research/nowplaying.md`](docs/research/nowplaying.md).

## Permissions and data

TopNotch is **not sandboxed**. The drop shelf needs arbitrary file access and playback
control needs Apple Events, neither of which survives the sandbox for a Developer ID app
distributed outside the App Store.

It asks for:

- **Apple Events**, to control Spotify and Apple Music when the system route is unavailable.

Everything stays on your Mac. The only network traffic is the Sparkle update check against
this repo's GitHub releases; there are no analytics and no account.

| Data | Where it lives |
|---|---|
| Notes | `~/Library/Application Support/<bundle id>/`, plain JSON files |
| Dropped files | `~/Library/Caches/<bundle id>/DropShelf`, expiring copies |
| Pomodoro state, focused pane, launch-at-login flag | `UserDefaults` |

## Layout

| Module | Contains |
|---|---|
| `NotchCore` | Contracts, design tokens, motion, shared controls. Everything else reads from it and never modifies it. |
| `NotchShell` | The window, idle bar, proximity, pill row, pane host |
| `PaneMusic` | Now Playing, transport, artwork |
| `PaneDrop` | The temporary file shelf |
| `PaneNotes` | Quick notes |
| `PaneFocus` | Pomodoro |
| `TopNotch` | App entry and wiring |

Panes are strictly disjoint. A pane never imports another pane; anything shared belongs in
`NotchCore`.

## Contributing

Read [`DECISIONS.md`](DECISIONS.md) first. It records the design decisions that are settled
and why, including what was rejected. Anything marked LOCKED is not up for redesign, and a
PR that quietly reverses one will be closed. If you think a locked decision is wrong, open
an issue and argue it there rather than in code.

The house rules, in short:

1. Style through `Style` and `Metrics`. No raw colours, fonts, corner radii or paddings.
2. Animate through `Motion`. No literal durations, no bare `.animation(.default)`.
3. Components move, they never swap. An element that exists in two states translates and
   scales between them. Cross-fading one element out and a different one in is forbidden.
4. Nothing renders inside the camera housing. It is a physical hole with no pixels.
5. Respect Reduce Motion, via `Motion.reduced(_:)` or the `notchAnimation` modifier.
6. Cheap when idle. The app sits on screen all day: no polling loops while nothing is
   happening, no timers firing when the notch is closed and the feature is inactive.
7. Swift 6 strict concurrency. UI types are `@MainActor`, anything crossing an actor
   boundary is `Sendable`.
8. `swift build` must pass with zero warnings.

Commits are semantic and short: `type(scope): subject`, imperative, lowercase.

## Acknowledgements

- [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) - BSD 3-Clause,
  the reason system-wide Now Playing works at all on a modern macOS.

## License

MIT, see [`LICENSE`](LICENSE).
