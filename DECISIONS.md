# DECISIONS

Locked design and product decisions for TopNotch. Read this before proposing or building anything.
Do not re-litigate what is here. Append new entries as decisions get made.

Status key: **LOCKED** = decided, build it exactly this way. **OPEN** = still being decided.

---

## UI / UX

### Expanded panel layout - **LOCKED**
Mode pills. A row of pills (Music, Drop, Notes, Focus) sits at the top of the expanded
panel. Clicking one morphs the panel's height and content to whatever that feature needs.
One feature visible at a time, each getting the full panel width.

Rejected: a left icon rail with a fixed-size content pane (too narrow); live tiles showing
all four features at once (too dense, panel too wide).

### Idle notch - **LOCKED**
The notch widens by roughly 65px per shoulder so content sits **inside** the black surface,
never floating detached beside it.

- Left shoulder: album art
- Right shoulder: live audio-reactive waveform
- Bottom edge: progress bar spanning the **full width** of the notch

When audio stops, all three retract to zero width and the notch settles back to exactly its
hardware dimensions, becoming invisible.

The physical camera housing is a real cutout with no pixels behind it. Nothing may ever be
drawn in that region. Content only occupies the shoulders flanking it.

### Expand animation - **LOCKED**
Components **move**, they never hide and reappear. Album art, waveform and progress bar are
persistent elements that translate and scale from their idle coordinates to their expanded
coordinates. On expand the bottom-edge progress bar detaches from the border and becomes the
scrubber. Cross-fading a component out and a different one in is forbidden.

There is a proximity state between idle and expanded: when the cursor comes within range the
notch breathes slightly wider before any hover, acknowledging without committing.

### Panel material - **LOCKED**
Liquid Glass, the native macOS 26 material: translucent, blurred, saturated, with a specular
edge highlight. The idle notch stays pure black so it reads as hardware; the material
transitions to glass on expand.

### Motion - **LOCKED**
Everything animates. Spring easing, roughly `cubic-bezier(.22, 1.08, .36, 1)` at ~0.46s for
the panel morph. Honour `prefers-reduced-motion`.

### Idle slots and the focus rule - **LOCKED**

The idle notch is driven by one focused pane plus a permanent pomodoro slot.

**Left, outermost - pomodoro.** A running pomodoro always occupies a dedicated slot at the far
left, showing a progress ring and countdown. It never rotates away and never yields the slot.

**Left, inner - focused identity.**
- Music playing: album art.
- Music not playing: the active pane's glyph.
- Exception: if music is off and the active pane is Focus, no glyph is drawn, because the
  pomodoro chip already on the left is the identity. Do not render a redundant second marker.

**Right - rotating slot.** Cycles the focused pane's live value first, then any other pending
signal (files held, note count). Items **slide vertically** through a fixed-width slot like a
slot machine. They never cross-fade, which would violate the move-don't-swap rule. Anything
already parked on the left is skipped so nothing appears twice. If there is nothing to show,
the slot collapses to zero width and the notch narrows.

**Focus rule.** The notch stays on the pane the user last landed on, closed or open, and
remembers it across launches. Opening the notch lands on that pane.

Music is the only exception. When playback starts it takes focus, because a track starting is
about the machine rather than about a pane somebody picked. It never does so under an open
panel: the switch waits until the notch has been closed for three seconds, and reopening the
panel restarts that wait. It fires once per track starting, so choosing another pane while
music plays sticks, and a deliberate choice cancels a switch that is still waiting.

Superseded on 2026-07-30: the original rule recomputed focus live from whichever live pane had
the highest priority, so the notch moved off the user's choice on its own and moved back the
moment music stopped. Priority now only breaks ties between simultaneous claims.

Rejected: a dot cluster for pending items (needs a hover to decode, no live values); giving
every feature its own permanent shoulder (notch width becomes unpredictable).

### Pane navigation when expanded - **LOCKED**
Horizontal scroll and trackpad swipe move between panes. **No scrollbar is ever visible.** Snap
to the nearest pane on release. Pills at the top act as an indicator and a jump target. The
panel morphs its height to whatever pane lands. A vertical mouse wheel also scrolls sideways so
a plain mouse works.

---

## Features

### Now Playing source - **LOCKED**
Read system-wide Now Playing, not Spotify-only. Apple Music, YouTube in a browser, podcasts
and VLC all get identical controls. Spotify additionally gets launch-and-resume so the notch
can start it when it is not running.

Risk accepted: this uses a private macOS framework that Apple hardened in macOS 15.4+. Verify
it works on macOS 26.5 before building on it, and fall back to per-app AppleScript if dead.

Rejected: Spotify AppleScript only (no other players); Spotify Web API (needs OAuth, network,
and only covers one app).

### Quick notes encryption - **LOCKED**
Notes are **public by default** and open with no prompt at all. Any individual note can be
marked private, and a private note requires Touch ID to open. This mirrors Apple Notes.

Rejected: locking the entire notes feature behind Touch ID (too much friction for a scratchpad).

### Menu bar item and settings - **LOCKED**
There is one status item in the menu bar, and it is the only chrome outside the notch. It holds
the basic settings and preferences: open the notch, launch at login, quit.

It exists because settings have to live somewhere findable. The app has no dock icon and no
window, so without it there is no way to turn launch-at-login off from inside the app.

Supersedes the earlier "no dock icon, no main window and no menu bar item" position, which was
written before anything needed a setting.

### Launch at login - **LOCKED**
On by default, registered through `SMAppService.mainApp`. The notch is only worth anything if it
is already there, and an app you have to remember to start is one you stop using.

The default is applied exactly once, on first launch. After that the user's choice stands,
including one made in System Settings rather than in our menu. The menu re-reads the real
registration state every time it opens, so it can never claim the app starts at login when
macOS says otherwise.

Rejected: a `LaunchAgent` plist (invisible to the user in System Settings, and orphaned if the
app is deleted); a separate helper target (a whole extra bundle to sign and ship for one bool).
