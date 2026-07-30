# Screenshot shot list

`01-idle-music.png` is already captured (idle notch, artwork + waveform + progress line).
The rest need a human hand: hovering the notch cannot be automated without granting the
terminal Accessibility permission, and the panel captures the desktop behind its shadow,
so take these with a clean wallpaper and nothing sensitive near the top of the screen.

Capture command for each (region is centred on the notch of the built-in display):

```bash
# Idle bar only:
screencapture -x -R "550,0,700,60" NN-name.png
# Expanded panel (press the shortcut, then you have 5 seconds to hover the notch open):
sleep 5 && screencapture -x -R "560,0,680,420" NN-name.png
```

| # | File | Setup |
|---|---|---|
| 1 | `01-idle-music.png` | Done. Retake if you want different album art showing. |
| 2 | `02-expanded-music.png` | Music playing, hover the notch open on the Music pane. Shows artwork grown into place, scrubber, transport. |
| 3 | `03-expanded-drop.png` | Drag two or three files onto the notch first so the shelf has chips in it. |
| 4 | `04-expanded-notes.png` | A couple of throwaway notes, one marked private so its blurred title shows. Do not use real notes. |
| 5 | `05-expanded-focus.png` | Pomodoro running, so the pane shows the ring mid-session. |
| 6 | `06-idle-focus.png` | Close the panel with the pomodoro still running: idle notch with the ring and live countdown parked on the left. |

Keep them at 2x (Retina) as captured. For a GitHub release page or website, 2-4 shots
are plenty; 1, 2 and 6 tell the story fastest.
