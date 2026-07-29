# Now Playing on macOS 26.5 - research and verification

Research date: 2026-07-28. Test machine: macOS 26.5 (25F71), arm64, Swift 6.3.3.
Everything marked VERIFIED was executed on this machine and the real output is included.

---

## Summary

| Question | Answer | Confidence |
|---|---|---|
| Does raw unentitled MediaRemote work on 26.5? | **No.** Symbols resolve, callbacks fire, payload is `NIL` | VERIFIED |
| Does the perl adapter still work on 26.5? | **Yes.** Full metadata plus artwork plus transport control | VERIFIED |
| Does it work under Hardened Runtime? | **Yes** | VERIFIED |
| Does it work under App Sandbox? | **Yes, if the helper is bundled inside the .app** | VERIFIED |
| Does it need a TCC prompt? | **No prompt of any kind** | VERIFIED |
| Is there a public App Store-safe API for this? | **No** | VERIFIED (negative) |
| Does the Swift package build under Swift 6 mode? | **Yes**, ran and returned live data | VERIFIED |
| What does the biggest OSS notch app ship? | boring.notch vendors this exact adapter | VERIFIED |
| Biggest risk | CVE-2026-43723 hardened MediaRemote path handling in **26.6**, shipped 2026-07-27 | REPORTED |

**Recommendation: primary =** `mediaremote-adapter` perl shim, bundled in-app, `stream` mode.
**Fallback =** per-app AppleScript for Spotify and Apple Music, selected at runtime by the adapter's own `test` exit code.

---

## 1. Raw MediaRemote unentitled - dead

Built an unentitled ObjC binary that `dlopen`s the framework and calls the classic functions.

Source: `scratchpad/mrtest/mrtest.m`. **VERIFIED** output:

```
dlopen handle=0x365c65178 err=none
sym MRMediaRemoteGetNowPlayingInfo                       -> FOUND
sym MRMediaRemoteRegisterForNowPlayingNotifications      -> FOUND
sym MRMediaRemoteSendCommand                             -> FOUND
sym MRMediaRemoteGetNowPlayingApplicationIsPlaying       -> FOUND
sym MRMediaRemoteGetNowPlayingClient                     -> FOUND
sym MRMediaRemoteSetElapsedTime                          -> FOUND
sym MRNowPlayingClientGetBundleIdentifier                -> FOUND
GetNowPlayingApplicationIsPlaying -> 0
GetNowPlayingInfo callback fired. dict=NIL count=0
callbacks fired: 2 (expected 2)
```

What exactly fails:

- `dlopen` succeeds. The framework is in the dyld shared cache, there is no on-disk Mach-O at `Versions/A/MediaRemote`.
- Every symbol resolves. There is no link-time or load-time error.
- The **callbacks still fire**. They just deliver `NIL` / `false`.
- So the failure is silent and looks identical to "nothing is playing". Do not treat `NIL` as "no media", it is indistinguishable from "denied".

Ground truth at that same moment (**VERIFIED**): Spotify was running with `squabble up` by Kendrick Lamar loaded and paused. So `NIL` was a denial, not an empty state.

`mediaremoted` performs the entitlement check server-side. Processes whose signing identifier starts with `com.apple.` are allowed through. REPORTED: this gate landed in macOS 15.4.

Corroboration (REPORTED, gathered during the parallel feature survey): boring.notch issue **#417** tracks exactly this breakage and carries **54 reactions**. **FB17228659** (feedback-assistant/reports #637) asks Apple for a public now-playing API and is still open with no response. `aviwad/LyricFever` issue #94 is the same `NIL` symptom.

---

## 2. The perl adapter - alive on 26.5

### Repo state, VERIFIED by clone

`ungive/mediaremote-adapter`, cloned fresh.

- Latest commit on master: **2026-04-26** `3ac3d4b`.
- Issue tracker is active into **June 2026**. Issue #26 is a seek bug reported specifically on **Tahoe 26.2**, fixed by #34 on 2026-05-03. Issue #37 closed 2026-06-24.
- The README badge says "last tested Jul 2025 / macOS 26.0" but that badge is stale. The commits and issues are the real signal.
- REPORTED: `ungive/media-control` is the CLI wrapper (`brew install media-control`) and vendors this repo as a submodule pinned at the same `3ac3d4b`.

### How the trick works, VERIFIED by reading source and codesign

```
codesign -dv /usr/bin/perl
Identifier=com.apple.perl
Platform identifier=26
CodeDirectory ... flags=0x0(none)
```

Two properties make it work, and both are load-bearing:

1. Signing identifier is `com.apple.perl`, which satisfies the `com.apple.` prefix allowance in `mediaremoted`.
2. `flags=0x0(none)` means **no hardened runtime and no library validation**. That is what lets perl `dlopen` a third-party framework. If Apple ever adds library validation to `/usr/bin/perl`, the trick dies instantly.

The perl script loads the adapter with `DynaLoader::dl_load_file` and installs the C entry point as an XSUB (`mediaremote-adapter.pl:112,270,272`). The adapter framework then talks to MediaRemote itself, inheriting perl's identity.

The adapter does **not** link MediaRemote. **VERIFIED** via `otool -L`: only Foundation, AppKit, UniformTypeIdentifiers, CoreFoundation, ImageIO, libSystem, libobjc. It resolves MediaRemote at runtime from `/System/Library/PrivateFrameworks/MediaRemote.framework`.

However, **VERIFIED** via `strings`, the private symbol names and the private framework path are plain text in the binary:

```
MRMediaRemoteSendCommand
MRMediaRemoteGetNowPlayingInfo
MRMediaRemoteRegisterForNowPlayingNotifications
/System/Library/PrivateFrameworks/MediaRemote.framework
```

Runtime dlopen dodges the linker, not App Review's static scanner.

### Live proof on 26.5

Built the framework with CMake (clean build, ad-hoc signed). **VERIFIED** output, with the
track and title strings redacted and everything structural left exactly as captured:

```
$ perl mediaremote-adapter.pl <fw> <testclient> test
test exit code = 0        # 0 means the adapter is entitled and functional

$ perl mediaremote-adapter.pl <fw> get --now -h
{
  "playbackRate" : 0,
  "album" : "",
  "elapsedTimeNow" : 122.146007,
  "elapsedTime" : 122.146007,
  "timestamp" : "2026-07-28T16:34:07Z",
  "bundleIdentifier" : "company.thebrowser.Browser",
  "processIdentifier" : 47408,
  "title" : "<page title>",
  "duration" : 335.62729300000001,
  "artist" : "",
  "contentItemIdentifier" : "654C7982-...",
  "playing" : false
}
```

Note it picked up a **browser video**, not Spotify. This is genuinely system-wide, which is what `DECISIONS.md` locked in.

With Spotify playing, **VERIFIED** full payload including artwork:

```
album              str    '<album>'
mediaType          str    'kMRMediaRemoteNowPlayingInfoTypeAudio'
trackNumber        int    1
elapsedTime        float  2.794
timestamp          str    '2026-07-28T16:34:51Z'
bundleIdentifier   str    'com.spotify.client'
processIdentifier  int    836
artworkData        str    <171188 chars base64>
artworkMimeType    str    'image/jpeg'
title              str    '<track>'
duration           float  274.192
artist             str    '<artist>'
playing            bool   False
```

Artwork decoded to a real 600x600 JPEG, 128391 bytes. **VERIFIED**.

Full key set the adapter exposes (**VERIFIED** from `src/adapter/keys.m`): album, artist, artworkData, artworkMimeType, bundleIdentifier, chapterNumber, composer, contentItemIdentifier, duration, elapsedTime, elapsedTimeNow, genre, isAdvertisement, isBanned, isInWishList, isLiked, isMusicApp, mediaType, parentApplicationBundleIdentifier, playbackRate, playing, processIdentifier, prohibitsSkip, queueIndex, radioStationHash, radioStationIdentifier, repeatMode, shuffleMode, startTime, supportsIsBanned, supportsIsLiked, timestamp, title, totalChapterCount, totalDiscCount, totalQueueCount, totalTrackCount, trackNumber, uniqueIdentifier.

### What shipping apps actually do

**VERIFIED** via the GitHub trees API: **`TheBoredTeam/boring.notch`** (10,176 stars, last push **2026-07-25**, four days before this research) vendors the adapter directly into its repository as prebuilt artifacts:

```
mediaremote-adapter/mediaremote-adapter.pl
mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/_CodeSignature/CodeResources
mediaremote-adapter/MediaRemoteAdapterTestClient
```

Their `Package.resolved` (**VERIFIED**) lists Sparkle, Defaults, KeyboardShortcuts, LaunchAtLogin-Modern, Lottie, Pow, SkyLightWindow, swiftui-introspect and others, but **no media dependency**. They check in the compiled framework rather than taking a SwiftPM dependency or building from source.

That is the strongest available signal: the largest open-source notch app, actively shipping in the last week, is on exactly this path, including the `MediaRemoteAdapterTestClient` health check. It also tells you the preferred integration shape: **vendor the prebuilt artifacts and sign them as part of your app**, which keeps the build reproducible and avoids a revision-pinned dependency.

### Push, not poll - and the real latency

`stream` mode pushes newline-delimited JSON. It is event driven off `MRMediaRemoteRegisterForNowPlayingNotifications`, so it satisfies rule 7 in `CLAUDE.md` (no polling loop).

**VERIFIED** latency, measured by timestamping stream lines against the wall clock at which each action was issued:

| Action | Latency to first stream event |
|---|---|
| Spotify `play` | **208 ms** (full payload at 239 ms) |
| `send 4` next track | **175 ms** |
| `send 1` pause | **68 ms** |

Sub-250 ms in all cases, and transport commands demonstrably worked (the track actually changed).

Payloads are diffs by default. A diff looks like:

```
{"type":"data","diff":true,"payload":{"playing":false}}
```

Pass `--no-artwork` for the idle path. **VERIFIED**: with artwork a single event is ~171 KB of base64; without it, well under 1 KB. Fetch artwork only when the identifying track keys change.

### Helper cost

**VERIFIED**, streaming continuously for 40 s:

```
  PID    RSS  %CPU ELAPSED
94066  25296   0.0   00:20
94066  25408   0.0   00:40
```

25 MB RSS, 0.0% CPU idle. RSS crept 112 KB over 20 s. Issues #20 and #21 were memory leaks fixed in Aug 2025, but watch it anyway and consider recycling the helper daily. Killing the parent left no orphan (**VERIFIED**, `pgrep` empty after kill).

### Distribution: what survives what

All three **VERIFIED** on this machine with ad-hoc signatures.

| Configuration | Result |
|---|---|
| Plain unsigned binary spawning perl | works |
| Hardened Runtime, `flags=0x10002(adhoc,runtime)` | **works** |
| App Sandbox, helper **outside** the bundle | **fails**: `Can't open perl script ...: Operation not permitted` |
| App Sandbox, helper **inside** `Contents/Resources` + `Contents/Frameworks` | **works** |

The sandboxed .app result, verbatim:

```
=== SANDBOXED .app, adapter bundled INSIDE ===
child exit=0 bytes=391
title=Serve  artist=Khantrast  bundle=com.spotify.client  playing=1
```

Why: the spawned perl child inherits the parent's sandbox, so it can only read paths the container permits. The app bundle is readable, `/private/tmp` is not.

**No TCC prompt appeared at any point.** No Accessibility, no Automation, no Full Disk Access. This is a real advantage over the AppleScript fallback.

Consequences for TopNotch:

- **Developer ID + notarization: fine.** Hardened Runtime is satisfied. Sign the bundled `MediaRemoteAdapter.framework` with your Developer ID and let it be sealed inside the app.
- **Mac App Store: technically works, will be rejected on policy.** Sandbox is not the obstacle. The private symbol strings are, and App Review scans for exactly those. Do not plan on the App Store with this path.

### Risk - read this before building

REPORTED, and this is the one thing that could invalidate everything above: **CVE-2026-43723** covers *path handling in MediaRemote* allowing a malicious app to gain root, "addressed by reinforcing validation in the affected path-handling logic". It shipped in **macOS 26.6 on 2026-07-27**, which is two days before this research and one point release ahead of this machine.

"Path handling validation" is uncomfortably close to the mechanism the adapter depends on. **This has not been tested on 26.6.** Retest `test` exit code on 26.6 before shipping.

Mitigation, and it is cheap: the adapter ships a `test` command whose exit code is a first-class health signal (0 = functional). Run it at launch and route to the AppleScript fallback when it is non-zero. Build this from day one, not as a later patch.

---

## 3. Public App Store-safe API - there is none

Honest answer: **no public API exposes another application's now-playing metadata or transport control on macOS.**

- `MPNowPlayingInfoCenter` is **write-only for your own process**. You publish what *you* are playing. `default.nowPlayingInfo` reads back only what you set.
- `MPRemoteCommandCenter` registers handlers for commands sent *to* you. It does not send commands to others.
- `MPMediaLibrary` / `MPMediaQuery` are iOS-only and cover the local library, not playback state.
- `AVRoutePickerView` is audio routing, not metadata.
- Nothing in the macOS 26 SDK adds a now-playing observer entitlement.

The only sanctioned adjacent surface is `NSAppleEventsUsageDescription` plus per-app AppleScript, which is the documented fallback below and is App Store-acceptable with the right entitlement.

---

## 4. Option comparison

| | perl adapter (`stream`) | perl adapter (`get`) | Per-app AppleScript | Raw MediaRemote |
|---|---|---|---|---|
| Works on 26.5 | **yes** (VERIFIED) | yes (VERIFIED) | yes (VERIFIED) | **no** (VERIFIED) |
| Coverage | system-wide, any app | system-wide | Spotify + Music only | n/a |
| Helper process | yes, 1 perl, 25 MB | yes, per call | no (in-process NSAppleScript) | no |
| Push or poll | **push** | poll | **poll only** | push |
| Latency | 68-239 ms (VERIFIED) | ~120 ms per call | ~135 ms per `osascript` (VERIFIED) | n/a |
| Artwork | raw JPEG bytes inline | same | **URL only, needs network** | n/a |
| TCC prompt | **none** (VERIFIED) | none | **Automation prompt** | none |
| Sandbox | yes, if bundled (VERIFIED) | same | yes, with entitlement | n/a |
| Notarization | yes (VERIFIED) | yes | yes | n/a |
| App Store | **no**, private symbols | no | **yes** | no |
| Fragility | Apple can close it | same | very stable | already closed |

---

## 5. Ranked recommendation

### Primary: `mediaremote-adapter`, `stream` mode, bundled in-app

It is the only option that satisfies the LOCKED decision in `DECISIONS.md` ("read system-wide Now Playing, not Spotify-only"), it pushes rather than polls, it delivers artwork bytes directly, and it needs zero permission prompts.

Integration: use the **`ejbills/mediaremote-adapter` fork**, a real SwiftPM package. The upstream README endorses it: "For a maintained Swift package look at this excellent fork".

**VERIFIED end to end.** I added it as a dependency to a throwaway package, built it under **`.swiftLanguageMode(.v6)`**, and ran it on this machine:

```
Building for debugging...
Build complete! (0.41s)
=== RUN under Swift 6 language mode ===
title=It's Too Cold to Be Sad Today, Don't You Think? artist=Proportions PH playing=true
Parent process died, terminating
```

It compiles clean under Swift 6 language mode with no Sendable diagnostics, including passing `TrackInfo` into a `@MainActor` context (VERIFIED). It also kills its own helper when the parent dies, which is the behaviour you want.

Public API (**VERIFIED** from `Sources/MediaRemoteAdapter/MediaController.swift`): `startListening()`, `stopListening()`, `getTrackInfo(_:)`, callbacks `onTrackInfoReceived` / `onListenerTerminated` / `onDecodingError`, and `play() pause() togglePlayPause() stop() nextTrack() previousTrack() setTime(seconds:) toggleShuffle() toggleRepeat() startForwardSeek() endForwardSeek() startBackwardSeek() endBackwardSeek() goBackFifteenSeconds() skipFifteenSeconds() likeTrack() banTrack() addToWishList() removeFromWishList() setShuffleMode(_:) setRepeatMode(_:)`.

`TrackInfo.Payload` fields (**VERIFIED**): `title, artist, album, isPlaying, durationMicros, elapsedTimeMicros, applicationName, bundleIdentifier, artworkDataBase64, artworkMimeType, timestampEpochMicros, PID, shuffleMode, repeatMode, playbackRate`, plus a decoded `artwork: NSImage?`, a `uniqueIdentifier` and a `currentElapsedTime` that already does the extrapolation for you.

Three caveats before you adopt it:

- **No semver tags exist** (VERIFIED, `git ls-remote --tags` returns 0). You must pin by `branch: "master"` or, better, `revision:`. Pin a revision so an upstream push cannot break your build. Latest commit is `cf30c4f`, **2026-06-02**.
- The default branch is **`master`**, not `main`. Pinning `branch: "main"` fails resolution (VERIFIED).
- `swift-tools-version:5.5` and `MediaController` is a plain non-`Sendable`, non-isolated `public class`. Strict concurrency does not extend into it, which is why the build is clean. Callbacks arrive off the main thread, so hop to `@MainActor` yourself before touching UI state.

If you would rather own the process handling and avoid a pinned-by-revision dependency, drive perl directly. The snippet below does that and is built only from things verified above.

### Fallback: per-app AppleScript, gated on the adapter's `test` exit code

Not a replacement, a degradation. Covers Spotify and Apple Music only, polls, and artwork for Spotify is a URL you must fetch over the network.

### Rejected

- Raw MediaRemote: dead, VERIFIED.
- Spotify Web API: OAuth, network dependency, one app only. Already rejected in `DECISIONS.md`.
- Accessibility-API scraping of player UIs: needs an Accessibility TCC prompt, breaks on every player redesign.

---

## 6. Minimal working Swift for the primary path

Layout inside the app bundle, required for sandbox compatibility (VERIFIED):

```
TopNotch.app/Contents/Resources/mediaremote-adapter.pl
TopNotch.app/Contents/Frameworks/MediaRemoteAdapter.framework
```

```swift
import Foundation

struct NowPlaying: Decodable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?          // seconds
    var elapsedTime: Double?       // seconds, valid as of `timestamp`
    var timestamp: Date?
    var playing: Bool?
    var playbackRate: Double?
    var bundleIdentifier: String?
    var artworkData: Data?         // decoded from base64 by JSONDecoder
    var artworkMimeType: String?
    var contentItemIdentifier: String?

    /// Elapsed time extrapolated to now. Avoids polling just to move a progress bar.
    func elapsed(at now: Date = .now) -> Double {
        guard let base = elapsedTime else { return 0 }
        guard playing == true, let ts = timestamp else { return base }
        let rate = playbackRate ?? 1
        return min(base + now.timeIntervalSince(ts) * rate, duration ?? .infinity)
    }
}

/// MRCommand IDs, VERIFIED from the adapter README table.
enum MRCommand: Int {
    case play = 0, pause = 1, togglePlayPause = 2, stop = 3
    case nextTrack = 4, previousTrack = 5
    case toggleShuffle = 6, toggleRepeat = 7
    case goBackFifteen = 12, skipFifteen = 13
}

actor MediaRemoteBridge {
    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private let script: URL
    private let framework: URL
    private var streamTask: Process?

    init(bundle: Bundle = .main) throws {
        guard let s = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let f = bundle.privateFrameworksURL?
                        .appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: f.path)
        else { throw CocoaError(.fileNoSuchFile) }
        self.script = s
        self.framework = f
    }

    private func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = perl
        p.arguments = [script.path, framework.path] + args
        return p
    }

    // MARK: - Health check. Exit code 0 means MediaRemote access still works.
    // Run at launch; if this is non-zero, fall back to AppleScript.
    func isFunctional() -> Bool {
        guard let client = Bundle.main.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient")
        else { return false }
        let p = Process()
        p.executableURL = perl
        p.arguments = [script.path, framework.path, client.path, "test"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // MARK: - Push stream. One long-lived helper, event driven, no polling.
    /// `includeArtwork: false` keeps each event under 1 KB instead of ~170 KB.
    func stream(includeArtwork: Bool = true) -> AsyncStream<NowPlaying> {
        AsyncStream { continuation in
            var args = ["stream", "--no-diff"]      // --no-diff = every event is complete
            if !includeArtwork { args.append("--no-artwork") }
            let p = makeProcess(args)
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice

            let decoder = JSONDecoder()
            decoder.dataDecodingStrategy = .base64
            decoder.dateDecodingStrategy = .iso8601

            var buffer = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                buffer.append(handle.availableData)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<nl]
                    buffer.removeSubrange(...nl)
                    guard !line.isEmpty,
                          let env = try? decoder.decode(Envelope.self, from: Data(line)),
                          env.type == "data",
                          let payload = env.payload,
                          payload != NowPlaying()      // adapter emits a leading `{}`
                    else { continue }
                    continuation.yield(payload)
                }
            }
            p.terminationHandler = { _ in continuation.finish() }
            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                if p.isRunning { p.terminate() }
            }
            do { try p.run() } catch { continuation.finish() }
            self.streamTask = p
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let payload: NowPlaying?
    }

    // MARK: - Transport
    func send(_ c: MRCommand) { fireAndForget(["send", String(c.rawValue)]) }
    func play()      { send(.play) }
    func pause()     { send(.pause) }
    func toggle()    { send(.togglePlayPause) }
    func next()      { send(.nextTrack) }
    func previous()  { send(.previousTrack) }

    /// Seek. The adapter takes MICROSECONDS, not seconds.
    func seek(toSeconds seconds: Double) {
        fireAndForget(["seek", String(Int(seconds * 1_000_000))])
    }

    private func fireAndForget(_ args: [String]) {
        let p = makeProcess(args)
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
    }

    func stopStream() {
        streamTask?.terminate()
        streamTask = nil
    }
}
```

Usage:

```swift
let bridge = try MediaRemoteBridge()
guard await bridge.isFunctional() else { /* switch to AppleScript fallback */ return }

Task {
    for await np in await bridge.stream(includeArtwork: true) {
        // np.title, np.artist, np.album, np.artworkData,
        // np.elapsed(), np.duration, np.playing
    }
}
await bridge.next()
await bridge.seek(toSeconds: 42)
```

Three notes that will save time:

- **`elapsedTime` is a snapshot, not a live clock.** Extrapolate from `timestamp` and `playbackRate` as `elapsed(at:)` does. Do not re-run `get` on a timer to animate the progress bar.
- **Fetch artwork only when the track identity changes.** Key off `contentItemIdentifier`. Run the idle stream with `--no-artwork` and pull artwork separately, or you burn 170 KB per event.
- **Signing.** `MediaRemoteAdapter.framework` must be signed with your Developer ID and sealed in the bundle. Ad-hoc worked locally (VERIFIED) but will not notarize.

---

## 7. Fallback: per-app AppleScript

### Spotify dictionary, VERIFIED on this machine

Dumped with `sdef /Applications/Spotify.app`, Spotify **1.2.94.583**.

Commands: `next track`, `previous track`, `playpause`, `pause`, `play`, `play track`.

| Property | Type | Access |
|---|---|---|
| `current track` | track | r |
| `sound volume` | integer | rw |
| `player state` | ePlS (`playing`/`paused`/`stopped`) | r |
| `player position` | real (seconds) | **rw** - this is your seek |
| `repeating enabled` / `repeating` | boolean | r / rw |
| `shuffling enabled` / `shuffling` | boolean | r / rw |

Track properties: `artist`, `album`, `album artist`, `disc number`, `duration` (integer, **milliseconds**), `played count`, `track number`, `starred`, `popularity`, `id`, `name`, `artwork url`, `artwork` (image data), `spotify url`.

**Artwork gotcha, VERIFIED.** The dictionary advertises `artwork` as `image data`, but it does not work:

```
osascript -e 'tell application "Spotify" to return (count of (artwork of current track as string))'
13          # 13 chars = the string "missing value"
```

So the historical claim holds: **`artwork url` is the only usable path**, and it needs a network fetch.

```
https://i.scdn.co/image/ab67616d0000b273ef9f74d482a73596d876962d
```

Read timing, **VERIFIED**, one `osascript` round trip pulling seven fields: **135 ms**. In-process `NSAppleScript` with a compiled, cached script is materially faster, but it is still a poll.

```
Serve, Khantrast, Serve, 132923, 67.994003295898, playing, https://i.scdn.co/...
```

Note `duration` is `132923`, milliseconds. Divide by 1000. `player position` is seconds as a float.

### Launching Spotify from not running

`tell application "Spotify" to play` will **auto-launch** Spotify, because sending any Apple Event to a non-running app launches it. The problem is it can block for seconds during launch, and a `play` sent too early is dropped.

Check first, then launch, then wait for readiness before commanding:

```swift
import AppKit

func ensureSpotifyThenPlay() async {
    let id = "com.spotify.client"
    let running = !NSRunningApplication
        .runningApplications(withBundleIdentifier: id).isEmpty

    if !running {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: id) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false            // do not steal focus from the notch
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)

        // Poll for the scripting interface to answer, not just for the process to exist.
        for _ in 0..<40 {                          // up to ~4 s
            try? await Task.sleep(for: .milliseconds(100))
            if runAppleScript("tell application \"Spotify\" to return player state as string") != nil {
                break
            }
        }
    }
    _ = runAppleScript("tell application \"Spotify\" to play")
}

@discardableResult
func runAppleScript(_ source: String) -> String? {
    var err: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
    if let err { NSLog("AppleScript error: \(err)"); return nil }
    return result?.stringValue
}
```

Never call `NSAppleScript.executeAndReturnError` on the main thread. It blocks, and during a cold Spotify launch it can block long enough to hitch the notch animation.

**The "is it running" trap.** Several ways of asking launch the app as a side effect, which is the opposite of what you want. Measured:

| Form | Launches the app? | Time |
|---|---|---|
| `NSWorkspace.runningApplications` | **no** | **0.003 s** |
| `running of application id "..."` at top level | no | 0.05 s |
| `application "X" is running` at top level | no | 0.05 s |
| `tell application "X" to get running` | **YES** | 0.95 s |
| `application "X" is running` **inside a `tell` block** | **YES**, then throws -1728 | - |

Inside a `tell` block `application "X"` resolves as an addressable target, so the query is dispatched to the app and forces a launch before it can even fail. Use `NSWorkspace` for the check, as the snippet above does. Cold launch blocks the caller: ~0.77 s for TextEdit, **~3.43 s for Music.app**, and Spotify is Electron so budget 3-10 s. `launch` is no better than `activate`; neither is asynchronous.

Two more details worth copying:

- Always address by **`application id "com.spotify.client"`**, never by name. A name that does not resolve pops a "Where is Spotify?" file chooser, which in a background menu-bar app is an invisible hang.
- `with timeout` bounds only the Apple Event send, not the LaunchServices launch phase, so it will not save you from a slow cold start.

### Apple Music

**VERIFIED** on this machine: Music.app **1.6.5**, `sdef` intact on macOS 26.5. `player state` (r), `player position` (**rw**, so seek works), `current track`, `sound volume` (rw), track `album` / `artist` / `duration` (real, seconds). Commands present: `play`, `pause`, `playpause`, `next track`, `previous track`, `back track`, `stop`.

REPORTED risk, not reproduced here: there are reports of Music.app AppleScript misbehaving on Tahoe (boring.notch issue #779). Music was not running during this research so an end-to-end live read was **not** tested. The dictionary is definitely present and well formed. Test a live read before relying on it.

Same shape as Spotify, better artwork. The `Music` app returns real bytes:

```applescript
tell application "Music"
    if player state is not stopped then
        set t to current track
        return {name of t, artist of t, album of t, duration of t, player position}
    end if
end tell
```

Artwork as raw data, which Spotify cannot do:

```applescript
tell application "Music" to return raw data of artwork 1 of current track
```

Returns a `TIFF`/`PNG`/`JPEG` blob you can hand straight to `NSImage`. `duration` here is **seconds** (a real), unlike Spotify's milliseconds. `player position` is rw, so seek works.

### TCC and Automation

This shell already held Automation permission, so a live denial was **not** exercised. Prompt text and button labels below are **VERIFIED** by extracting them from the system TCC bundle on this machine; behaviour on denial is REPORTED.

**The exact prompt string on 26.5**, VERIFIED from `/System/Library/PrivateFrameworks/TCC.framework/Resources/Localizable.loctable`:

```
REQUEST_ACCESS_SERVICE_kTCCServiceAppleEvents =
"%@" wants access to control "%@". Allowing control will provide access to
documents and data in "%@", and to perform actions within that app.
```

- **Buttons are "Don't Allow" and "Allow".** VERIFIED: the string `OK` has **zero** exact value matches in the 26.5 TCC table, while `Allow` and `Don't Allow` both appear. The widely repeated "Don't Allow / OK" is stale Mojave-era lore.
- Info.plist needs **`NSAppleEventsUsageDescription`**. REPORTED, and this corrects a common assumption: on macOS a missing key does **not** crash the app the way an iOS usage string does. You get a **silent, permanent -1743 with no prompt at all** and no TCC entry, which is far harder to diagnose. Put the key in the **main app**, not in a helper.
- The TCC service is **`kTCCServiceAppleEvents`**. The prompt fires **once per (source, target) pair**, so Spotify and Music are **two separate prompts**. Grants are bound to code-signing identity, so changing bundle ID or Team ID orphans every existing grant.
- Denial yields **-1743** `errAEEventNotPermitted`. Also handle **-1744** `errAEEventWouldRequireUserConsent`, returned when you pass `kAEDoNotPromptForUserConsent`. You cannot re-prompt programmatically once denied; surface a link to System Settings > Privacy & Security > Automation.
- REPORTED: users saw Automation grants **reset across the Tahoe upgrade**. Handle -1743 at runtime rather than assuming a grant persists.
- Do **not** call `AEDeterminePermissionToAutomateTarget` on the main thread. Apple's own header warns against it, and it has been observed blocking indefinitely in `semaphore_wait_trap` even with `askUserIfNeeded = false`.
- Reset during development: `tccutil reset AppleEvents com.yourcompany.topnotch`.

### Sandbox entitlements - corrected

This is the part most write-ups get wrong.

| Entitlement | Actually belongs to | Verdict |
|---|---|---|
| `com.apple.security.automation.apple-events` | **Hardened Runtime, not App Sandbox** | Opens no sandbox hole. Needed for Developer ID, not for MAS. |
| `com.apple.security.scripting-targets` | App Sandbox | **Current and preferred.** |
| `com.apple.security.temporary-exception.apple-events` | App Sandbox | Fallback only. REPORTED, Apple DTS: "tantamount to shipping a non-sandboxed app". QA1888 says requests targeting Finder or System Events "will likely result in rejection". |

You do **not** need a temporary exception for Spotify. `scripting-targets` is enough, and it is keyed to *access groups* the target app declares in its own `sdef`.

**VERIFIED** by reading the installed dictionaries on this machine:

| Target | Access group | Covers |
|---|---|---|
| Spotify | `com.spotify.playback` | `application` class, and `play`, `pause`, `playpause`, `next track`, `previous track` |
| Spotify | `com.spotify.library` (read) | the `track` class, meaning **title, artist, album, duration, artwork url** |
| Music | `com.apple.Music.playback` | transport |
| Music | `com.apple.Music.library.read` | track metadata |
| Music | `com.apple.Music.library.read-write` / `com.apple.Music.user-interface` | not needed |

**The trap:** playback-only access groups silently lose all track metadata, because on both apps the metadata hangs off the `track` class which sits in a *different* access group. You get working transport controls and permanently empty title and artist. That failure mode appears only in the sandboxed build, so it presents as "works in my Developer ID build, broken in the MAS build".

You need **both** groups:

```xml
<key>com.apple.security.scripting-targets</key>
<dict>
  <key>com.spotify.client</key>
  <array>
    <string>com.spotify.playback</string>
    <string>com.spotify.library</string>
  </array>
  <key>com.apple.Music</key>
  <array>
    <string>com.apple.Music.playback</string>
    <string>com.apple.Music.library.read</string>
  </array>
</dict>
```

---

## 8. Priority 2 - artwork colour extraction

### Benchmark, VERIFIED on this machine

Real 600x600 JPEG album art (128 KB) pulled from the live now-playing payload. Swift 6.3.3, `-O`, 50 iterations, Apple Silicon.

```
source: 600x600, 128391 bytes

A  thumbnail(32) + weighted histogram [from Data] median   0.604 ms   p90 0.719 ms  | #4B5769 #56666F #667175
A2 thumbnail(64) + weighted histogram [from Data] median   0.540 ms   p90 0.588 ms  | #4A5769 #576670 #677275
B  CIAreaAverage  (1 colour, pre-decoded)        median   1.087 ms   p90 1.205 ms  | #69717E
C  CIKMeans k=3   (pre-decoded)                  median   3.832 ms   p90 3.984 ms  | #CFD3DA #9AA3AD #431E18
D  vImageScale 32 + histogram (pre-decoded)      median   0.545 ms   p90 0.562 ms  | #4B5769 #57666F #687374
```

| Approach | Time | Colours | Verdict |
|---|---|---|---|
| `CIAreaAverage` | 1.09 ms | **1 only, muddy grey** | Cannot produce 2-3 colours. Rejected. |
| `CIKMeans` k=3 | 3.83 ms | 3, perceptually good | 7x slower, and that **excludes** decode. GPU warm-up on first call. |
| `vImageScale` + histogram | 0.55 ms | 3, but near-duplicates | Requires a full 600x600 decode first. No advantage over A2. |
| **ImageIO thumbnail + weighted histogram** | **0.54 ms** | 3 | **Winner.** Includes decode. |

Two findings that matter more than the raw timings:

1. **`CIAreaAverage` is the wrong tool.** It returns the mean of every pixel, which for almost any album cover is a desaturated grey (`#69717E` here). It cannot give you 2-3 colours at all.
2. **A naive histogram returns three near-identical colours.** Look at run A2: `#4A5769 #576670 #677275` are three adjacent buckets of the same blue-grey. Useless for a two-tone tint. This is the trap, and it is a quality bug, not a perf one.

### Fix: drop extremes, weight by saturation, enforce minimum distance

Adding those three rules, **VERIFIED** re-run:

```
dominant (deduped): #4A5769 67%  #677274 24%  #8A92AA 8%
median 0.725 ms   p90 1.125 ms
```

0.725 ms for three genuinely distinct colours with population weights, straight from raw JPEG `Data`, including decode. Still 5x faster than `CIKMeans`.

### Recommendation

Use **ImageIO thumbnail decode plus a saturation-weighted, distance-deduped histogram**. No dependency, no GPU, no Core Image context to keep alive, ~0.7 ms. `CIKMeans` is the only alternative worth considering and only if you later want perceptually optimal palettes and can absorb 4 ms plus a `CIContext`.

```swift
import CoreGraphics
import ImageIO
import Foundation

/// Dominant colours from raw artwork bytes.
/// ~0.7 ms for a 600x600 JPEG on Apple Silicon (measured).
/// Decodes at reduced size via ImageIO, so cost is near-independent of source resolution.
func dominantColors(
    from data: Data,
    thumbnailSide: Int = 64,
    want: Int = 3,
    minDistance: Int = 60          // Manhattan distance in RGB, stops near-duplicates
) -> [(color: CGColor, fraction: Double)] {
    guard let src = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSide,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
    else { return [] }

    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
            .draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    // 8x8x8 = 512 bins.
    let bins = 8, shift = 5
    var count = [Int](repeating: 0, count: bins * bins * bins)
    var sumR = count, sumG = count, sumB = count

    for i in stride(from: 0, to: px.count, by: 4) {
        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
        let lum = (r * 299 + g * 587 + b * 114) / 1000
        if lum < 12 || lum > 245 { continue }        // ignore letterboxing and blown highlights
        let mx = max(r, max(g, b)), mn = min(r, min(g, b))
        let sat = mx == 0 ? 0 : (mx - mn) * 255 / mx
        let weight = 1 + sat / 24                    // colourful pixels count for more
        let k = (r >> shift) * bins * bins + (g >> shift) * bins + (b >> shift)
        count[k] += weight; sumR[k] += r * weight
        sumG[k] += g * weight; sumB[k] += b * weight
    }

    var picked: [(Int, Int, Int, Int)] = []
    for k in count.indices.filter({ count[$0] > 0 }).sorted(by: { count[$0] > count[$1] }) {
        let c = (sumR[k] / count[k], sumG[k] / count[k], sumB[k] / count[k])
        let farEnough = picked.allSatisfy {
            abs($0.0 - c.0) + abs($0.1 - c.1) + abs($0.2 - c.2) >= minDistance
        }
        if farEnough { picked.append((c.0, c.1, c.2, count[k])) }
        if picked.count == want { break }
    }

    let total = Double(picked.reduce(0) { $0 + $1.3 })
    guard total > 0 else { return [] }
    return picked.map {
        (CGColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255,
                 blue: CGFloat($0.2) / 255, alpha: 1),
         Double($0.3) / total)
    }
}
```

Call it once per track change, off the main actor, and cache against `contentItemIdentifier`. Never call it per frame.

---

## Appendix: reproducing the verification

```bash
git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git
cd mediaremote-adapter
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build

# health check, 0 = MediaRemote access works
/usr/bin/perl bin/mediaremote-adapter.pl \
  "$PWD/build/MediaRemoteAdapter.framework" \
  "$PWD/build/MediaRemoteAdapterTestClient" test ; echo "exit=$?"

# one-shot read
/usr/bin/perl bin/mediaremote-adapter.pl \
  "$PWD/build/MediaRemoteAdapter.framework" get --now -h

# live push stream
/usr/bin/perl bin/mediaremote-adapter.pl \
  "$PWD/build/MediaRemoteAdapter.framework" stream --no-artwork
```

Scratch artifacts from this session, if still present:
`scratchpad/mrtest/` (unentitled probe), `scratchpad/bench/` (colour benchmarks),
`scratchpad/SBTest.app` (sandbox test), `scratchpad/HRTest.app` (hardened runtime test).

### Sources

- https://github.com/ungive/mediaremote-adapter
- https://github.com/ungive/media-control
- https://github.com/ejbills/mediaremote-adapter
- https://support.apple.com/en-us/128067 (macOS Tahoe 26.6 security content)
- https://github.com/aviwad/LyricFever/issues/94 (macOS 15.4 breakage report)
