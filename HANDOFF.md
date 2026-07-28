# HANDOFF

Live coordination file for the parallel build. **Delete this file once everything is merged
and verified** so it never becomes stale context.

Started: 2026-07-29

## State

| Agent | Owns | Status |
|---|---|---|
| research | `docs/research/` | **done**, use the vendored perl adapter, gate on its self-test |
| shell | `Sources/NotchShell` | running |
| music | `Sources/PaneMusic` | running |
| drop | `Sources/PaneDrop` | built, 111 checks pass; sent back to fix a nested scroll conflict |
| notes | `Sources/PaneNotes` | **done**, branch `worktree-agent-ad2c2ad0919cb852b`, 25 crypto tests pass |
| focus | `Sources/PaneFocus` | **done**, branch `worktree-agent-ae3eee291b0064743`, 34 tests pass |

Base commit every agent branched from: `57fa2d5`.

## Rules the agents were given

- `OPINIONS.md` is the locked spec. Nothing in it gets redesigned.
- One module per agent. `NotchCore` is read-only for all of them.
- All styling through `Style` and `Metrics`, all animation through `Motion`.
- Components move between states, never cross-fade.
- Nothing renders inside the camera housing.
- `swift build` with zero warnings before reporting done.

## Known open threads

- **Now Playing on macOS 26.5.** The private MediaRemote framework was restricted around
  macOS 15.4. The research agent is verifying whether it, or the perl-adapter workaround,
  still works. The music agent is building behind a `NowPlayingSource` protocol with a
  working AppleScript conformer, so this cannot block the build. Wire the verified source
  in once the research lands.
- **Keystrokes in a non-activating panel.** A `TextEditor` inside an `NSPanel` that does not
  activate may not receive key events. The notes agent is solving this and may need
  cooperation from the shell. Reconcile at merge.
- **Auto-expand on drag.** The drop agent exposes an API for the shell to call when a drag
  enters the top-of-screen region while the notch is collapsed. Wire it at merge.
- **Shared namespace for `matchedGeometryEffect`.** The shell defines an environment key so
  panes can adopt the shared namespace for artwork and the scrubber. Pass the key name to
  the music agent after the shell reports.

## NotchCore gaps to apply AFTER all agents merge

Do not touch `NotchCore` while agents are in flight; they are compiling against it.
Collect requests here and apply them in one pass at merge.

- Add a test target to `Package.swift`. The focus agent has 34 passing tests parked in a
  scratch package because there is nowhere in the repo to put them. Same will apply to notes.
- `IdleItem.ring(progress:label:)` takes a pre-formatted string, so the idle countdown only
  advances when the shell re-reads it. Add a `Date`-carrying variant so the shell can render
  a live countdown without waking the pane.
- No way for a pane to ask the notch for a brief flourish. Add a pulse token to `IdleSignal`
  so pomodoro completion can be acknowledged by the notch itself, not just in-pane.
- `NotchButton` has no selected state, so toggles are being faked with tiles.
- `Metrics` has no pane-internal spacing scale; panes are defining private layout enums.
- No AppKit equivalents of `Style.body` / `Style.ink` for code that hosts an `NSTextView`,
  no list row spacing metric, no blur token.

## Orchestrator bugs to fix at merge

- **`Resources/TopNotch.entitlements` ships a literal `$(AppIdentifierPrefix)`.** SPM plus
  `codesign --sign -` never substitutes it, so `keychain-access-groups` is malformed and an
  unentitled Keychain probe returns `-34018`. Either drop the group entirely (the app is the
  only consumer of its own items) or substitute the real team prefix in `Scripts/bundle.sh`.
  Notes cannot be verified end to end until this is fixed.
- Add a `.testTarget` to `Package.swift`. Notes has 25 XCTest cases parked behind
  `#if TOPNOTCH_TESTS` and focus has 34 in a scratch package. Both want a home.

## Merge order

1. `shell` first, since it defines the environment contracts everything else adopts.
2. Panes in any order after that; they touch disjoint directories.
3. Orchestrator wires `Sources/TopNotch` and reconciles the three open threads above.
4. Build, bundle, launch, verify on the real notch.
5. Delete this file.
