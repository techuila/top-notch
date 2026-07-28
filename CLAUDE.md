# TopNotch

A macOS 26 notch app. Music, a file drop shelf, encrypted quick notes and a pomodoro,
all living in the MacBook notch.

**Read `OPINIONS.md` first.** It holds every locked design decision. Anything marked
LOCKED is settled - build it exactly as written, do not redesign it, do not "improve" it.

## Build

```
swift build            # compile
./Scripts/bundle.sh    # produce build/TopNotch.app
```

There is no `.xcodeproj` on purpose. A generated pbxproj cannot be merged, and several
agents work this repo in parallel. Do not add one.

## Module ownership

Each module has exactly one owner. Never edit a module you do not own; if you need
something from another module, it belongs in `NotchCore` instead, and you ask for it.

| Module | Owner | Contains |
|---|---|---|
| `NotchCore` | orchestrator | Contracts, design tokens, motion, shared controls. **Read-only for everyone else.** |
| `NotchShell` | shell agent | The window, idle bar, proximity, pill row, pane host |
| `PaneMusic` | music agent | Now Playing, transport, artwork |
| `PaneDrop` | drop agent | The temporary file shelf |
| `PaneNotes` | notes agent | Quick notes and encryption |
| `PaneFocus` | focus agent | Pomodoro |
| `TopNotch` | orchestrator | App entry and wiring |

## Rules that are not negotiable

1. **Never edit `NotchCore`.** If a token, metric or shared control is missing, say so in
   your report. Do not add a local copy and do not hardcode a value that belongs there.
2. **Style through `Style` and `Metrics`.** No raw colours, fonts, corner radii or paddings.
3. **Animate through `Motion`.** No literal durations, no bare `.animation(.default)`.
4. **Components move, they never swap.** Elements that exist in two states translate and
   scale between them. Cross-fading one element out and a different one in is forbidden.
5. **Nothing renders inside the camera housing.** It is a physical hole with no pixels.
6. **Respect Reduce Motion.** Use `Motion.reduced(_:)` or the `notchAnimation` modifier.
7. **Cheap when idle.** The app sits on screen all day. No polling loops that run while
   nothing is happening, no timers firing when the notch is closed and the feature is
   inactive, no retained decoded images beyond what `ArtworkCache` holds.
8. **Swift 6 strict concurrency.** UI types are `@MainActor`. Anything crossing an actor
   boundary is `Sendable`.
9. `swift build` must pass with zero warnings before you report done.

## Style

No em dashes anywhere, including comments and commit messages. Use hyphens.
Semantic commits, short, no body unless genuinely non-obvious, no AI attribution.
