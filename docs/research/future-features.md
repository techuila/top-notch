# TopNotch - Future Feature Research

Research date: 2026-07-29. Target: macOS 26.5 Tahoe, Swift 6.3 + SwiftUI, Apple Silicon, Developer ID.

Out of scope (already being built): media/now-playing control, file drop shelf, quick notes, pomodoro timer.

Every claim is tagged **[V]** VERIFIED (I read the repo/issue/vendor page/API doc directly) or **[R]** REPORTED (blog, review site, aggregator, forum, secondhand).

**Sourcing caveat:** Reddit blocked every access path tried (search API 400, WebFetch 403 on `reddit.com`/`old.reddit.com`, Redlib mirrors 403). **No r/macapps or r/MacOS claim in this document is verified.** The substitute primary-voice corpus is `TheBoredTeam/boring.notch` GitHub issues (10.2k stars, 318 open issues, timestamped, with reaction and comment counts), plus Hacker News, MacRumors forums, Product Hunt and Apple Discussions. Vendor comparison tables (notchy.dev, crestnotch.app, getdroppy.app, favtray.com, notchbay.com) are written by competing notch-app vendors and score themselves favourably; treat their competitor columns as marketing, not audit.

---

## 1. Ranked shortlist (value / cost)

Cost key: XS = under a day, S = 1-3 days, M = 1-2 weeks, L = 3-6 weeks, XL = quarter+.
Risk key: how likely Apple or an OS update breaks it.

| # | Feature | Value | Cost | Risk | Ships in | Demand evidence |
|---|---------|-------|------|------|----------|-----------------|
| 1 | Notch sizing + always-on sneak peek + hotkey hide | High | XS | None | Most apps | boring.notch #300 (+5), #797 (+7), #1353, #1045, #969, #1037 [V] |
| 2 | AirPods / peripheral battery + connect reveal | High | S | Low | Alcove, Notchy, NotchNook, DynamicLake | boring.notch #206 (5 rx), #1387, #694, #985, #418 [V] |
| 3 | Non-notch Mac support (software pill) | High | S | Low | DynamicLake, NotchNook, MediaMate, Notchy | boring.notch #1176, #263 [V] |
| 4 | Calendar next-meeting countdown + one-click Join | High | S-M | Low | NotchNook, Bartender Top Shelf, DynamicLake | boring.notch #216 (+2), #151, #1352, #1235 [V] |
| 5 | AI coding session monitor (Claude Code / Codex / Cursor) | High | S | Low | Notchy, Crest, Droppy, FavTray [R] | boring.notch #951 (+3), #1104 (+1) [V] |
| 6 | Caffeine toggle + audio output switcher + system-wide mic mute | Med-High | S | None | Notchy | boring.notch #1310 (11 comments), #270 [V] |
| 7 | Liquid Glass adoption | Med-High | S | Low | DynamicLake "Liquid Glass Mode" [R] | boring.notch #922 (10 rx), #913 [V] |
| 8 | Battery live activity + power actions ("charge to full") | Med-High | S | Low | Alcove, Boring Notch | boring.notch #621 (+2), #1093 (8c), #725, #796 [V] |
| 9 | Camera/mic privacy indicator | Med-High | M | Med | NotchBay, Notchy, NotchNook [R] | notchbay.com [V] |
| 10 | On-device dictation (SpeechAnalyzer, macOS 26 only) | High | M | Low | NotchBay, NotchNook, seam, Droppy [R] | notchbay.com [V] |
| 11 | Weather widget (WeatherKit) | Med | S-M | Low | DynamicLake DynaGlance, Bartender, Notchy | boring.notch README roadmap [V] |
| 12 | Shortcuts runner | Med | S | Low | NotchNook, Notchy | notchy.dev, lo.cafe [R] |
| 13 | Camera mirror + teleprompter | Med | S-M | Low | NotchNook, Boring Notch, Notchy | boring.notch #351 (+8), #1255, #436, #521 [V] |
| 14 | On-device AI assistant (Foundation Models) | Med-High | M | Low | Crest, FavTray, Perch, Droppy [R] | boring.notch #1104 (9 rx), #934, #1315 [V] |
| 15 | Download-finished alert + progress | Med | S-M | Low | Notchy, Droppy [R] | notchy.dev table [R] |
| 16 | Live system stats (CPU/RAM/net) | Med | S-M | Low | Atoll, Notchy, Crest | boring.notch #1082 [V] |
| 17 | Third-party calendar sources (Google/Outlook/Notion) | Med | M | Low | none well | boring.notch #1270, #1235, #1001 [V] |
| 18 | App launcher / command palette / Spotlight-in-notch | Med | M | Low | Notchy (⌃⌥K), Droppy, Crest | boring.notch #1006 [V] |
| 19 | Clipboard history (+ OCR search, pins) | High | M | **High** | NotchBay, Bartender, Notchy, Perch | boring.notch #780 (+2) [V] |
| 20 | Notification mirroring in the notch | High | L | **High** | DynamicLake, Alcove, Peninsula, NotchBay | boring.notch #592 (13 rx, highest open) [V] |
| 21 | Meeting controls (Zoom/Meet/Teams mute + leave) | Med-High | M-L | **High** | NotchBay, NotchNook, DynamicLake, Droppy | notchbay.com [V] |
| 22 | Window snapping by dragging to the notch | Med | M | Med | Notchy, Crest, Droppy | notchy.dev [R] |
| 23 | Reactive audio visualizer (real FFT) | Low-Med | M | **High** | none properly | boring.notch #234 (+3), #96 (+4) [V] |
| 24 | Focus mode indicator/switcher | Med | M | **High** | Notchy (detect), MediaMate (filters) | boring.notch #936 [V]; see dead ends |
| 25 | System HUD replacement (vol/brightness/kbd) | Med | L | **High** | Boring Notch, MediaMate, Alcove, DynamicLake | boring.notch #943 (17c), #953, #1055, #874 [V] |
| 26 | Screen Time / app usage module | Low-Med | M | Med | none | boring.notch #1327 [V] |
| 27 | Cmd-Tab window switcher replacement | Med | L | Med | Celve/Peninsula | Peninsula README [V] |
| 28 | Text snippets / expander | Low-Med | L | **High** | Notchy | notchy.dev [R] |
| 29 | Virtual desktop / Space indicator | Low | M | **High** | none | boring.notch #443 (+2) [V] |
| 30 | Lock screen presence | Low-Med | L | **Very high** | Alcove, DynamicLake Pro [R] | boring.notch README roadmap [V] |
| 31 | Extension / plugin SDK | Med | XL | Med | none shipped | boring.notch README roadmap [V] |

---

## 2. Dead ends and blocked on macOS 26.5

Read this section before committing to anything above.

| Thing | Status | Detail |
|-------|--------|--------|
| **Real iPhone Live Activities relay** | **Dead** | Live Activities on Mac arrive only via iPhone Mirroring and render in Apple's own menu bar surface. No public API to enumerate or re-render them; no third-party entitlement exists. boring.notch #671 (+3) explicitly asks for it and notes it would need private APIs [V]. Apple docs describe it as a user-facing Continuity feature only [R]. |
| **MediaRemote now-playing (private)** | **Entitlement-locked** | macOS 15.4 added entitlement checks in `mediaremoted`; only Apple-entitled processes get NowPlaying. boring.notch #417 has 54 reactions on exactly this break [V]. FB17228659 (feedback-assistant/reports #637) requests a public API, still open, no Apple response [V]. Workarounds: `ungive/mediaremote-adapter` (shells out to entitled `/usr/bin/perl` + injected helper framework - what boring.notch v2.7 uses [V]) or `MediaRemoteWizard` (requires SIP off, unshippable) [R]. Relevant to you since media control is in scope. |
| **Focus mode detection via `~/Library/DoNotDisturb/DB/Assertions.json`** | **Broken on Tahoe** | The file moved/changed on macOS 26; the classic polling approach no longer works [R, `eugenehp/macos-focus`, `swizzlevixen/busylight` #91]. Only supported path is `SetFocusFilterIntent` (AppIntents, macOS 13+), which requires the user to manually add your app's filter to each Focus - so you learn about a Focus only if the user opts in per-Focus. No global "which Focus is on" read. |
| **Notification Center SQLite DB** | **TCC-walled** | Moved in Sequoia to `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, which sits inside a TCC-protected Group Container [V, 9to5Mac]. Reading it needs Full Disk Access. There is no sanctioned system-wide notification interception API [R, Apple dev forum thread 758451]. Practical path is Accessibility (`AXObserver` on the Notification Center process) - which is what DynamicLake Pro appears to do, since it demands Accessibility + Notifications permissions [R]. |
| **External-display brightness via DDC** | **Degraded** | Apple Silicon DDC needs private `IOAVServiceReadI2C` / `IOAVServiceWriteI2C`. On Tahoe, MonitorControl reports it cannot access the new brightness meter, and `CGSetDisplayTransferByTable` no longer works on Apple Silicon built-in displays with auto-brightness on, breaking BetterDisplay/Lunar/f.lux/MonitorControl [V, MonitorControl #1778, #1847, discussions #1799, #1873; Apple forum 795074]. If you ship a brightness HUD you will also **conflict** with those apps - boring.notch #943 (+4) is a user whose BetterDisplay broke because boring.notch swallowed the key events [V]. |
| **Clipboard history** | **Prompt-walled** | macOS 15.4 previewed and macOS 26 ships pasteboard privacy: reading the general pasteboard *without* a paste-shaped user action triggers a user alert. A clipboard manager polling `changeCount` is precisely the pattern that prompts. New APIs help but don't exempt you: `NSPasteboard.accessBehavior` (always/never/ask) and `detectPatterns`/`detectValues` on `NSPasteboard`/`NSPasteboardItem` let you inspect *types* without reading content and without an alert [R, Michael Tsai / 9to5Mac / MacRumors, May 2025]. FB17587626 (feedback-assistant/reports #655) asks for a way to programmatically request full pasteboard access - open [R]. Plan for: type-only detection by default, content read gated behind an explicit user action or a one-time "always allow". |
| **Space / virtual desktop index** | **Private only** | `NSWorkspace.activeSpaceDidChangeNotification` is public but tells you only *that* it changed. Getting which Space requires `CGSCopyManagedDisplaySpaces` / `CGSGetActiveSpace` (private CoreGraphics) [R]. Fine for Developer ID, disqualifies App Store, and is Apple's to break. |
| **Answering phone calls from the notch** | **Dead** | boring.notch #414 (+2) [V]. No public API for Continuity call control. Every shipping "call island" is FaceTime/system-notification detection, not real call control [R]. |
| **Menu bar icon management** | **Hostile** | Tahoe broke the assumptions Bartender/Ice/Barbee relied on: `NSStatusItem.isVisible` returns true for icons hidden behind the notch, the OS reorders icons, positions get lost [R]. Ice development halted [R]. Do not build "hide menu bar icons" as a feature. |
| **Lock screen presence** | **Unsupported** | Alcove and DynamicLake Pro claim it [R]. macOS provides no supported way to render third-party UI on the lock screen. Assume private API or a login-window trick; assume it breaks. |
| **Bluetooth mic detection** | **Partial** | `kAudioDevicePropertyDeviceIsRunningSomewhere` works for built-in and wired mics but Bluetooth mics always report inactive [R, Apple forum 741026]. Your privacy indicator will have a known blind spot. |
| **`kCMIODevicePropertyDeviceIsRunningSomewhere`** | **Noisy** | Fires spuriously when unrelated apps (Music.app) launch; processes receive callbacks triggered by other processes' listener registration [R, Apple forum 697124]. Needs debouncing. |
| **Apple Music AppleScript (`fetchPlaybackInfoAsync`)** | **Broken on Tahoe** | boring.notch #779 (+8, 13 comments, open) [V]: on macOS 26 the Music scripting interface returns data only for *local library* files; Apple Music autoplay, radio and mood content return nothing, so controls still work but the UI never updates. Root cause traced by users to macOS Tahoe scripting changes [R, MacScripter thread 77173]. Do not build any media path on Music.app AppleScript. |
| **Custom `NSWindow` / `NSPanel` style masks** | **Flaky on 26.3+** | Reported erratic behaviour (unresizable / non-responsive windows) in Tahoe 26.3 RC specifically affecting OSD/HUD-style utilities [R]. Test your panel behaviour on every point release. |

---

## 3. Feature detail

### Tier A - build these first

#### A1. Notch geometry + visibility controls
- **Concretely:** user-settable open/closed width and height; a "sneak peek" strip that can be pinned permanently visible rather than auto-hiding; global hotkey to hide/show; auto-hide when nothing is active; hide while any app is fullscreen; per-external-display enable/disable.
- **Ships in:** every mature app; boring.notch shipped the fullscreen/external-display variants already (#239, #247, #137, #879 all closed completed) [V].
- **Cost:** XS. Pure SwiftUI layout + `UserDefaults` + `NSWorkspace` fullscreen notifications + a `HotKey`/Carbon `RegisterEventHotKey` binding. No TCC, no entitlements.
- **Demand [V]:** #300 (+5) width/height customisation, #797 (+7) permanently visible sneak peek, #1353 decrease open width, #1037 (+4) smaller music widget, #969 less notch area when inactive, #1045 manual hide/unhide, #1176 auto-disappear on non-notch Macs, #894 (+2) sneak peek delay setting, #1232 (+2) improved sneak peek control, #263 width on non-notch displays.
- **Why #1:** this is the single largest cluster of open requests in the biggest OSS competitor's tracker and it costs almost nothing. It is also the fix for the loudest complaint category ("it gets in the way").

#### A2. AirPods / peripheral battery + connect reveal
- **Concretely:** on AirPods connect, expand the notch with the device glyph, name, and per-bud + case battery (the iPhone-style reveal). Persistently show mouse/keyboard/trackpad battery in the closed notch, and cycle Mac battery -> headphone battery.
- **Ships in:** Alcove ("AirPods reveal", AirPods Max support) [R], Notchy (AirPods manager with per-bud battery, peripheral battery) [R], NotchNook [R], DynamicLake DynaConnect [R]. Boring Notch has it on its roadmap, not shipped [V].
- **APIs:** read IORegistry for `BatteryPercent`, `BatteryPercentLeft`, `BatteryPercentRight`, `BatteryPercentCase` under `AppleDeviceManagementHIDEventService` / `IOBluetoothDevice` via `IOServiceGetMatchingServices` + `IORegistryEntryCreateCFProperty`. IOKit itself is public; the property keys are undocumented but you are not calling a private function [R]. Connect/disconnect events: `IOBluetoothDevice.register(forConnectNotifications:)` (public, IOBluetooth) or `CBCentralManager`. Mac battery: `IOPSCopyPowerSourcesInfo` (public).
- **Cost:** S. No TCC prompt for IORegistry reads. Sandboxing would need `com.apple.security.device.bluetooth`; Developer ID unsandboxed is simplest.
- **Demand [V]:** #206 (5 reactions, 10 comments, open since Nov 2024), #1387 headphone battery, #694 (+5, closed dup) AirPods connect animation, #985 (+4, dup) different icon when AirPods connected, #418 (dup) headphone connect notification. Five separate filings = strong signal.

#### A3. Non-notch Mac support
- **Concretely:** on Macs with no physical notch (all Mac minis, Studios, iMacs, external displays, pre-2021 laptops), render a floating pill / capsule at top-center with the same behaviour. Optionally auto-hide it entirely until something happens.
- **Ships in:** DynamicLake (synthesises a notch, supports Intel + macOS 12) [R], NotchNook (transparent handler) [R], MediaMate (works on all Macs) [R], Notchy, Bartender Top Shelf (menu bar capsule with per-monitor placement) [R]. Atoll deliberately requires a physical notch and is criticised for it [R].
- **Cost:** S if the notch surface is already an `NSPanel` you position; you are changing geometry and adding a mask shape, not architecture.
- **Demand [V]:** boring.notch #1176 (auto-disappearing notch on non-notch Macs), #263 (set width on non-notch displays), #988 (+2, alternative look for multi-monitor).
- **Why it matters:** most installed Macs have no notch. This is a market-size multiplier, not a feature.

#### A4. Calendar countdown + one-click Join
- **Concretely:** closed notch shows "Standup in 4m" as the meeting approaches; expanding shows the event with a **Join** button that opens the Zoom/Meet/Teams link. Calendar picker so users choose which calendars count. Optional full-month view.
- **Ships in:** NotchNook (calendar with Join button) [R], Bartender Top Shelf (Calendar widget + meeting alerts) [R], DynamicLake DynaGlance [R], Boring Notch (calendar, no countdown/join) [V].
- **APIs:** EventKit. macOS 14+ requires `EKEventStore.requestFullAccessToEvents(completion:)` (the write-only/full split) - TCC prompt `NSCalendarsFullAccessUsageDescription`. Link extraction: regex `event.url`, `event.notes`, `event.location` for `zoom.us/j/`, `meet.google.com/`, `teams.microsoft.com/l/meetup-join`. Fire the countdown from a `Timer` keyed off `EKEventStore.events(matching:)` plus `.EKEventStoreChanged`.
- **Cost:** S-M. One TCC prompt, no entitlement, no helper.
- **Demand [V]:** #216 (+2) countdown to next meeting, #151 (closed completed) per-calendar picking, #1352 full month view, #1235 Notion Calendar integration.

#### A5. AI coding session monitor
- **Concretely:** a dot per active Claude Code / Codex / Cursor session in the closed notch - green = running, orange = waiting on a permission prompt, grey = idle - and expanding lists project name, elapsed time, last tool. Optionally token/cost accumulation for the day.
- **Ships in:** Notchy ("AI usage tracker across 60+ providers", "GitHub PR counter") [R], Crest ("Claude co-pilot") [R], Droppy ("AI coding HUD") [R], FavTray ("AI cost tracking", "CI verdicts", "port monitoring") [R]. Nobody in the paid tier does the *session-state* version well.
- **APIs:** none. Watch `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/` with `DispatchSource` / `FSEvents`, tail-parse JSONL. These paths are in the user home but not in a TCC-protected subfolder (unlike Desktop/Documents/Downloads), so no prompt.
- **Cost:** S for the file-watching + parsing; the format is unstable and you own the maintenance.
- **Demand [V]:** boring.notch #951 (+3, 8 comments) is a fully specified request for exactly this, including the colour semantics. PR #970 (7 reactions, 13 comments) is an actual community implementation attempt. #1196 is a third filing. Separately, **four independent Show HN launches of Claude-Code-status tools in 2026** (HN 47807159, 47785745, 48894825, 48886544) confirm the demand exists outside this one repo [V].
- **Why it ranks high:** it is the only feature on this list that a paying developer audience cannot get anywhere else in polished form, it needs zero permissions, and it is unbreakable by Apple.

### Tier B - cheap wins

#### B1. Caffeine / audio switcher / mic mute cluster
- **Caffeine:** `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleDisplaySleep` or `...SystemSleep`. Public, XS, no TCC. Ships in Notchy [R]. **Demand [V]:** boring.notch #1310, 11 comments - one of the most-discussed enhancement threads despite zero reactions, i.e. real conversation not drive-by voting.
- **Audio output switcher:** enumerate with `kAudioHardwarePropertyDevices`, set `kAudioHardwarePropertyDefaultOutputDevice`. Public CoreAudio, S, no TCC. Ships in Notchy [R], MediaMate shows output device icons in the volume HUD [R]. boring.notch #270 asks for it [V].
- **System-wide mic mute:** set `kAudioDevicePropertyMute` (or input volume 0) on the default input device. Public, S. Ships in Notchy [R].
- Bundle all three as a "toggles" row. Combined cost S, combined value decent.

#### B2. Liquid Glass adoption
- `glassEffect(_:in:)` / `GlassEffectContainer` in SwiftUI, `NSGlassEffectView` in AppKit, macOS 26+ [R, Apple newsroom + dev docs]. Since you are macOS 26.5-only you can adopt unconditionally with no back-compat branches - a real advantage over every competitor still supporting macOS 13/14.
- **Demand [V]:** boring.notch #922, 10 total reactions (+6 thumbs), second-highest open enhancement.
- **Caveat:** Tahoe's menu bar is fully transparent and legibility complaints are widespread [R]. Do not assume glass over an arbitrary wallpaper is readable; ship a solid/dimmed fallback and respect Reduce Transparency (which itself was broken until 26.3 [R]).

#### B3. Battery live activity
- `IOPSCopyPowerSourcesInfo` / `IOPSGetTimeRemainingEstimate` (public IOKit). Show: plugged-in animation, percentage, time-to-full/empty, low-battery warning at 20/10%, full-charge island.
- Ships in Alcove ("battery + charging alerts as a live activity") [R], Boring Notch (charging indicator) [V], Notchy [R].
- **Demand [V]:** #621 (+2) persistent battery live activity, #1093 (8 comments) "Charge to full button like native battery menu bar", #725 low-battery alert with countdown, #796 (+2) low power mode toggle.
- **Low Power Mode toggle specifically:** *reading* is free (`ProcessInfo.processInfo.isLowPowerModeEnabled`, plus `NSProcessInfoPowerStateDidChange`). *Toggling* requires `pmset -a lowpowermode 1` as root, i.e. an `SMAppService` privileged helper with its own install prompt. Ship the indicator, skip the toggle unless you already have a helper.
- **"Charge to full now" (#1093):** macOS optimised charging holds at 80%; the native battery menu has an override button. There is no public API for it - the state lives in `AppleSmartBattery` IORegistry and is set via SMC writes. Treat as private-API territory; showing the *state* ("holding at 80%") is free and covers most of the need.

#### B4. Weather
- WeatherKit (`WeatherService.shared.weather(for:)`). Needs Apple Developer Program membership, the `com.apple.developer.weatherkit` entitlement and a WeatherKit-enabled App ID, plus CoreLocation TCC for the user's location. 500,000 calls/month free per membership; you must display the Apple Weather trademark and the legal attribution link [R, Apple developer docs].
- Ships in DynamicLake DynaGlance, Bartender Top Shelf (with precipitation warnings), Notchy, FavTray [R]. On Boring Notch's roadmap, unshipped [V].
- **Cost:** S-M. The entitlement paperwork is the slow part, not the code.

#### B5. Shortcuts runner
- List available shortcuts: no public API; `shortcuts list` CLI via `Process` works but is blocked under App Sandbox. Run one: `shortcuts://run-shortcut?name=<name>` via `NSWorkspace.open` (no permissions at all), or expose your own `AppIntent`s so users build notch-triggered automations in Shortcuts.
- Ships in NotchNook, Notchy [R].
- **Cost:** S. Also gives you an AppIntents surface for free, which is the supported path for Focus filters (see dead ends).

#### B6. Camera mirror + teleprompter
- `AVCaptureSession` + `AVCaptureVideoPreviewLayer`, camera TCC (`NSCameraUsageDescription`). Add a device picker (`AVCaptureDevice.DiscoverySession`) - Continuity Camera shows up automatically.
- **Teleprompter** is the differentiated half: paste text, it scrolls in a strip directly under the notch so the presenter's eyes stay on the camera. Speed control, play/pause hotkey, mirrored option.
- **Demand [V]:** #351 (+8, third-highest open enhancement) teleprompter - a well-argued request; #436 mirror; #521 (+3) camera selection.
- **Ships in:** mirror in NotchNook, Boring Notch, Notchy [V/R]. Teleprompter: only Notchy claims it [R]. This is a cheap, genuinely-wanted gap.
- **Cost:** S-M.

#### B7. Downloads
- Watch `~/Downloads` with `FSEventStreamCreate` or `NSMetadataQuery` (`kMDItemFSName`). `~/Downloads` is TCC-protected since Catalina, so expect one prompt (`NSDownloadsFolderUsageDescription`). Progress: partial files carry `.download` (Safari), `.crdownload` (Chrome), `.part` (Firefox) suffixes - size-poll them for a percentage; on rename to the final name, fire the "done" island with a drag handle straight into the shelf you already have.
- Ships in Notchy (download-finished alerts) [R], Droppy [R].
- **Cost:** S-M. Pairs naturally with your existing drop shelf.

#### B9. On-device AI assistant
- **Concretely:** a small chat/ask surface in the expanded notch, plus useful applications of it: summarise the clipboard, rewrite selected text, name a dropped file, summarise the day's calendar.
- **APIs:** `FoundationModels` framework, macOS 26+. On-device, free, no API key, no network, no TCC prompt. `SystemLanguageModel.default.availability` gates on Apple Intelligence being enabled. This is the single best fit for a macOS 26-only app: every competitor that ships AI either bundles a cloud key (FavTray "Island Oracle" is bring-your-own-key, Crest "Claude co-pilot") or charges for it [R].
- **Demand [V]:** boring.notch #1104 (9 reactions) - the requester's argument is literally "other dynamic island apps have an AI assistant and boring.notch doesn't"; also #934, #1315.
- **Cost:** M. The model call is trivial; the work is deciding which three things it does well rather than shipping a generic chat box.
- **Caveat:** the context window is small and the model is weak relative to frontier models. Do not promise chat; promise specific transforms.

#### B10. Third-party calendar sources
- **Concretely:** Google Calendar, Outlook and Notion Calendar events that the user has *not* subscribed to in Apple Calendar.
- **Demand [V]:** boring.notch #1270 (Google), #1235 (Notion Calendar), #1001 (Outlook).
- **Reality check:** if the user adds the account in System Settings > Internet Accounts, EventKit already sees it and this costs nothing. The remaining request is for users who refuse to do that, which means OAuth, token storage, refresh, and a privacy policy. **Ship the EventKit path plus an in-app "add your Google account in System Settings" helper first**; only build real OAuth if support volume proves it.

#### B8. Live system stats
- `host_statistics64` (memory), `host_processor_info` (CPU), `getifaddrs` deltas or `NWPathMonitor` (network), `IOKit` `AGXAccelerator` for GPU. All public, no TCC.
- Ships in Atoll (independently toggleable CPU/GPU/memory/network/disk) [R], Notchy, Crest, FavTray [R].
- **Cost:** S-M. **Watch the poll rate** - this is the feature most likely to earn you the battery-drain complaints that plague NotchNook (see section 4). Sample at 2-5s, suspend on battery when the notch is closed, suspend entirely on display sleep.

### Tier C - expensive, high value, high risk

#### C1. Clipboard history
- **Concretely:** last N clips with type icons, pinning, search, OCR of copied images (Vision `RecognizeTextRequest`), secure-field/password exclusion.
- **Ships in:** NotchBay ("The Tray", OCR, latest 60 clips, pinning) [V], Bartender Top Shelf (thumbnails, retention, password exclusion, floating search hotkey) [R], Notchy (OCR + searchable), Perch ("Snippets"), DynamicLake DynaClip [R].
- **Cost:** M for the feature, but see the pasteboard-privacy entry in section 2 - the permission model is the actual work. Design for `detectPatterns` (type-only, silent) as the default and gate content reads.
- **Exclusion hygiene:** honour `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` markers that password managers set.
- **Demand [V]:** boring.notch #780 (+2) "a place for quick notes and Clipboard data".

#### C2. Notification mirroring
- **Concretely:** notifications from chosen apps render in/under the notch instead of the top-right corner; unread count badge; click to open.
- **Highest-voted open enhancement in boring.notch: #592, 13 reactions [V].** The requester explicitly cites DynamicLake's implementation as the bar.
- **Ships in:** DynamicLake (Accessibility + Notifications permissions) [R], Alcove [R], NotchBay ("Status Notifications") [V], Celve/Peninsula (per-app opt-in, icon shows 6.18s then collapses to unread count) [V], Bartender ("Dynamic Notifications") [R], Droppy (with inline replies) [R].
- **Cost:** L. Two viable paths, both bad:
  - **Accessibility:** `AXUIElementCreateApplication` on Notification Center, `AXObserverAddNotification` for `kAXCreatedNotification` / `kAXWindowCreatedNotification`, walk the element tree for title/body. Needs Accessibility TCC. Fragile across point releases and Liquid Glass restructured the banner hierarchy.
  - **Full Disk Access + SQLite** on `~/Library/Group Containers/group.com.apple.usernoted/db2/db`. TCC-walled since Sequoia [V]; asking a notch app for Full Disk Access is a conversion killer.
  - Neither suppresses the native banner. You cannot hide the system banner without Accessibility-driven dismissal, which races.
- **Verdict:** highest-demand item on the board and the one most likely to cost you a month and break in 26.6. Do it only after Tier A/B, and do it Peninsula-style (per-app opt-in icons + counts) rather than full content mirroring, which reduces the AX surface you depend on.

#### C3. Meeting controls
- **Concretely:** while in a Zoom/Meet/Teams call, the notch shows mute state and a leave button.
- **Ships in:** NotchBay (Zoom + Meet mute/leave) [V], NotchNook (Zoom/Meet mute+leave) [R], DynamicLake (FaceTime, Zoom, Meet, **Teams**) [R], Droppy [R].
- **Cost:** M-L, per-app.
  - Zoom: post its global mute hotkey via `CGEvent` (Accessibility TCC), or drive its UI with AXUIElement. Zoom exposes a configurable global shortcut, so this is the most reliable target.
  - Meet: it is a web page. AppleScript/JXA into Chrome/Safari (Apple Events TCC per-browser, `NSAppleEventsUsageDescription`) or AX on the browser web area. Breaks whenever Google reflows the DOM.
  - Teams: Electron, AX-drivable, similar fragility.
- **Cheaper substitute:** ship the **mic-in-use indicator + system-wide mic mute** (B1 + item 8) instead. It works in every conferencing app, needs no per-app integration, and covers the actual user need ("am I muted").

#### C4. System HUD replacement
- **Concretely:** replace macOS volume/brightness/keyboard-backlight OSDs with notch-anchored ones.
- **Ships in:** Boring Notch (shipped complete in v2.7, incl. keyboard brightness and percentage display) [V], MediaMate (its entire product), Alcove, DynamicLake DynaKeys [R].
- **Cost:** L and this is the highest-support-burden feature in the category. You must (a) install a `CGEventTap` on `NSSystemDefined` events to catch `NX_KEYTYPE_SOUND_UP/DOWN/MUTE`, `NX_KEYTYPE_BRIGHTNESS_UP/DOWN`, `NX_KEYTYPE_ILLUMINATION_UP/DOWN` - Accessibility + often Input Monitoring TCC; (b) suppress Apple's own OSD, for which there is no API (apps kill/relaunch `OSDUIHelper` or lean on `BezelServices`/`CoreDisplay` private calls).
- **Evidence this is a support tarpit [V]:** #943 (17 comments) BetterDisplay conflict, #953 (+2, 7 comments) brightness broken on external monitor, #1055 (+2) native HUD still shows when using an external keyboard, #1251, #1040 (dup, "two brightness bars for both displays, the app doesn't know which one to attach itself to"), #874 (+1, 5 comments) smoother brightness, #1016 (granting Accessibility intercepts keys and breaks other apps). Plus the Tahoe DDC breakage in section 2.
- **There is a supported escape hatch, and it changes the calculus [V]:** BetterDisplay ships an **OSD notification dispatch integration** (`Integration-features,-CLI#osd-notification-dispatch-integration` in its wiki). BetterDisplay can be programmatically configured to forward brightness/volume events and suppress its own OSD, so your app renders the HUD and BetterDisplay does the actual DDC work. In boring.notch #943 the BetterDisplay author (`@waydabber`) states **MediaMate and DynamicLake already use this**, offers help, and then **removed the Pro requirement for OSD integration** (free as of BetterDisplay v4.1.5, which also improved macOS 26.3 support). boring.notch's maintainer confirms this "will completely replace our MediaKeyInterceptor in the HUD logic when using BetterDisplay."
- **Revised verdict:** build the HUD as a *renderer* that consumes BetterDisplay's dispatch when BetterDisplay is installed, and only fall back to your own `CGEventTap` when it is not. That removes the worst conflict class and the DDC problem in one move, and you inherit external-display brightness for free. Still ship volume first, and still ship a global off switch. Note the fallback path also needs a per-display targeting rule - #943's own thread proposes routing by which screen the pointer is on.

#### C5. Reactive audio visualizer
- **Concretely:** a real spectrum bar/waveform that responds to what is actually playing, not a looping GIF.
- **Demand [V]:** #234 (+3) responsive visualizer, #96 (+4) static spectrogram, #1115 (+2) animated album art.
- **Cost:** M, and it is **gated on system-audio capture**. To FFT the output you need to tap system audio: on macOS 14.4+ that is `AudioHardwareCreateProcessTap` + `AudioHardwareCreateAggregateDevice` (public CoreAudio, requires audio-capture TCC on macOS 15+), or ScreenCaptureKit's `SCStream` audio capture (Screen Recording TCC). Both are heavyweight prompts for a decoration. `SCStream` also carries the purple recording indicator in the menu bar, which users will complain about.
- **Verdict:** the visual payoff is real but the permission cost is disproportionate. Approximate from the media source's own metadata (tempo, playing state) or ship a stylised non-reactive animation.

---

## 4. Things users complain about (build the antidote, not just features)

These recur across trackers and reviews. Every one is a wedge against the incumbents.

| Complaint | Evidence | What to do |
|-----------|----------|------------|
| **Idle CPU / battery drain - the #1 uninstall trigger** | [V] boring.notch #1260 (10 comments, open): *"Even when nothing is running (no audio playing and the notch isn't in view), BoringNotch is eating 10% CPU with 40-60% battery usage."* Maintainer's own stated target: *"When collapsed, even with music playing, it should be 0-1% CPU."* [R] NotchNook: 2GB+ RAM after hours, ~5%/hr idle drain, dev quoted on Discord telling users to roll back to 1.4.6 (MacRumors thread 2463695) | Suspend every timer when collapsed and on display sleep. Publish your idle CPU number as a marketing claim. Also: **your marketing site must not be heavy** - HN 44627590 (80pts/88c) is a notch-app launch where the landing page itself cooked people's phones |
| **Crashes/disappears after sleep, unkillable** | [V] boring.notch #336, **44 comments**, still open across 15.3-15.5 on M2/M3/M4: *"I cannot force quit the app because it does not show in the list of open apps in the force quit menu. The only option was to close and restart my user session."* | Rebuild the panel on `NSWorkspace.didWakeNotification` and `CGDisplayRegisterReconfigurationCallback`. Never be a non-`LSUIElement`-visible process that can't be quit; always keep a menu bar quit path |
| **Multi-monitor display pinning - unsolved by everyone** | [V] boring.notch #174 (9 comments, spans 2.1-2.3, still open): app jumps to the external display on wake/reconnect. Triggers: projector reconnect, sleep/wake, clamshell overriding `preferredScreen`, KVM switches, dual externals ("the monitor that wakes up first gets the notch"). Best user framing: *"the default should be the built-in screen since the external monitor is highly unlikely to have a real notch."* Also #1281 (overlay on non-notched external in clamshell), #892 (1px line at top), #988 (+2) | Default to built-in, persist the choice by display UUID not index, never re-elect on wake. This is the clearest open wedge in the category |
| **Fullscreen conflicts** | [V] #663 (7c) notch won't hide in fullscreen, #814 fullscreen traffic lights persist while hovering, #1359 macOS fullscreen bar gets *stuck*, #1278 notch covers content. HN 35546068 (75pts/79c) on the underlying grievance | Explicit fullscreen policy with per-app exclusions, tested against the stuck-menu-bar case |
| **Permission fatigue** | [V] #1350: *"no matter how many times I enable accessibility permissions, it keeps asking me for them constantly"* - root cause was a **helper binary inside the bundle needing its own grant**. #779 fix is `sudo tccutil reset All`. #1016: granting Accessibility intercepts volume/brightness keys and breaks other apps. [R] Alcove's developer publicly markets engineering *around* "creepy permissions" and avoiding "the keyboard access requirement that many competing applications demand" | Request nothing at launch, degrade gracefully per feature, and avoid separate-binary helpers that need their own TCC grant |
| **Uninstall leaves remnants** | [V] #1282 and #784: the app still appears in macOS 26 Tahoe's menu-bar settings pane *after complete uninstall*. #623: cursor still misbehaves at the notch after uninstall **and a clean macOS install** - users blame the app for permanent damage | Ship an explicit "Uninstall TopNotch" command that removes defaults, login items, TCC-adjacent artifacts, and caches |
| **Animation jank - users want an off switch, not better wobble** | [V] #303 (16 reactions, 14 comments, ~10 distinct users): the animation *overshoots the physical notch cutout exposing the hardware* ("it really breaks the illusion"), "always seems to wobble to the left", "goes absolutely bonkers on my external monitor". #364 (+26), #341 (12r/15c) stuttering, #316 (8r/14c). Two of the four most-reacted issues in the entire repo are requests to disable an animation | Every animation gets an off switch, and no animation ever exceeds the physical notch bounds |
| **Breaks on every macOS update** | [V] #417 (54 reactions, macOS 15.4 MediaRemote), #779 (+8, macOS 26 Apple Music), #1044 (drag-out from shelf fails on 26.3), #1354 (Homebrew cask hard-refuses on Tahoe) | Minimise private-API surface; ship a public "what broke" status page |
| **Abandonment anxiety** | [V] boring.notch's last stable release is v2.7.3, **2025-11-24 - eight months stale** with 318 open issues. HN 47743138 and 47749945 both call it out. In #1350 a user installs an **unsigned stranger's build from a GitHub comment** to get an unmerged feature | Visible release cadence is itself a feature in this category |
| **Unnotarized / scary install** | [V] boring.notch README admits no Apple Developer account; #905 (+4, 6c) asks for install guidance. MewNotch #50: "MacOS declares it as malware" | You already plan Developer ID - make notarization and signing a marketing point |
| **Subscription resentment and price cuts** | [R] NotchNook launched at $39.99, cut to $24.99 (-37%) with no compensation to early buyers; refunds described as hard. [V] Product Hunt on Alcove: *"NotchNook is the paid alternative and there are free alternatives that are better than this too."* [V] HN 44627590: *"$7 for something that can be done for free in iTerm"* | One-time pricing, set once, never cut. Also [V] HN 41182234: NotchNook had ~$100k in sales frozen by Stripe - pick your payment processor with that in mind |
| **macOS-version gating loses buyers** | [V] Product Hunt: *"Increasingly feeling left out of many apps"* from a user excluded by a Sonoma+ requirement | Your macOS 26.5 floor is a real cost. It buys you Liquid Glass, `SpeechAnalyzer` and `FoundationModels` with no back-compat branches - make sure the roadmap actually cashes that in, or the floor is pure downside |

**Tahoe changed the visual premise [R]:** the macOS 26 menu bar is fully transparent and **no longer masks the notch with a dark bar**, and Reduce Transparency was itself broken in 26.1/26.2 before being fixed in 26.3 (osxdaily, Tom's Guide). Every notch app built before Tahoe assumed a dark menu bar behind it. Design for an arbitrary wallpaper directly behind your chrome.

**Pricing benchmark [R]:** MediaMate $6.99 · Droppy $6.99 · getpeninsula $10 · FavTray ~$12 lifetime · Alcove $14.99-$17 (3 devices, 72h trial) · DynamicLake Pro $16.90 (3 devices, lifetime updates, 14-day refund) · Bartender 6 $20 + Top Shelf needs Pro at $15/yr · NotchBay $19 promo / $39 list (1 Mac) · Crest $19.99 · seam $19.90 · NotchNook $25 one-time (5 devices) or $3/mo (2 devices) · Perch $3.99/mo-$49.99 lifetime · Notchy and Boring Notch free. The paid centre of gravity is **$15-$20 one-time**; free OSS is a live ceiling on anything above that.

---

## 5. Naming warning

"TopNotch" / "Top Notch" is heavily occupied [R]:
- **TopNotch** (topnotch.app), free, from the CleanShot X team - blacks out the menu bar to hide the notch. Well known since 2021.
- **Top Notch - Enhance Your Notch App** on the Mac App Store (id6760805803), 11 widgets.

Worth resolving before any public launch or ASO spend.

---

## 6. Suggested sequencing

0. **Non-negotiable foundations (not features, but they decide retention):** near-zero idle CPU, survives sleep/wake/clamshell/KVM, display pinned by UUID with built-in as default, always force-quittable, a real uninstaller, every animation defeatable and bounded by the physical cutout.
1. **Ship-blocking polish (XS-S):** notch geometry + pinned sneak peek + hotkey hide, non-notch pill, Liquid Glass, per-display instances.
2. **First differentiators (S):** AirPods/peripheral battery + connect reveal, battery live activity, calendar countdown + Join, AI coding session monitor, caffeine/audio-switcher/mic-mute toggles.
3. **Second wave (S-M):** weather, Shortcuts runner, camera mirror + teleprompter, downloads, system stats, camera/mic privacy indicator.
4. **macOS 26-only moats (M):** on-device dictation via `SpeechAnalyzer`, on-device assistant via `FoundationModels`. Competitors supporting macOS 13/14 cannot follow without a second code path. This is the payoff for your OS floor.
5. **Considered bets (M-L):** clipboard history built on the new pasteboard-privacy model, app launcher/command palette, HUD replacement *via BetterDisplay's OSD dispatch integration* rather than a raw event tap.
6. **Only if the above is solid (L+):** notification mirroring (highest demand, worst fragility - do the Peninsula per-app-icon variant, not full content mirroring), window snapping, window switcher.
7. **Do not build:** iPhone Live Activities relay, call answering, menu bar icon management, lock screen presence, Space index, Focus-state polling via `Assertions.json`, "charge to full" SMC writes.
