# Nine on Vision Pro — walkthrough shot list

`nine-vision-walkthrough.mp4` (1920×1080, 1:47), recorded 2026-10-23 on the
**Nine Vision** simulator (visionOS 27.0, `8ED61F7C-…`), DEBUG build of
`NineVision` at the Task 2 commit.

## Read this first: what kind of video this is

**It is a storyboard of simulator screenshots, not real-time footage.** Each
shot is one `simctl io screenshot`, held for 1.5–4 s. Two things forced that:

1. **No input could be injected.** The visionOS simulator vends no HID
   digitizer: every tap, swipe and button through the simulator control tool
   failed with `dtuhidServiceNotVended(com.apple.coredevice.feature.remote.hid.digitizer)`.
   Device Hub (Xcode 27's simulator window) was the remaining way to give real
   look-and-pinch input, and its control was declined. So every interaction
   below is driven by the DEBUG launch argument **`--vision-tour`**, which calls
   the same model methods a pinch on a cell or a key calls (`select`, `enter`,
   `erase`, `undo`, pencil mode, `compose`). The board's answers are real; the
   pinches are not.
2. **`simctl io recordVideo` starved the simulator.** It was used first, as
   asked: four takes at 3840×2160, 0.6–1 GB in all, with the machine's load
   average between 12 and 128. While recording, the simulator drew a new frame
   every ten seconds or more, so a whole solve collapsed into one frame and
   launches stalled for minutes on RealityKit scene setup. The raw takes are
   not committed. The storyboard instead advances one step per `vision-go`
   file (`--vision-wait-go`) and photographs each state after it has drawn.

Rendering lags the model by about one step, so some shots show the previous
step's answer arriving. That is noted where it happens.

## Shots

| Time | Shot | What it shows |
|---|---|---|
| 0:00 | Launch, resting | A fresh Gentle board, nothing selected: zero chrome, just the glass slab. |
| 0:04 | Resting (lag) | Same. The first `select` has been made but not drawn yet. |
| 0:06 | Select a cell | Top-left cell selected (the cursor highlight). The ornaments are still arriving. |
| 0:09 | Place a digit | A correct 3 settles in that cell. A second cell is selected; the **keypad** (trailing) and **New Game / Play together / Game Center** (bottom) ornaments are up. |
| 0:11 | Error | A wrong 6, in the error colour (the shake itself is a 0.3 s motion between shots). |
| 0:14 | Erase | The wrong digit is erased. |
| 0:16 | Place again | The right digit (5); every 5 on the board lights with it. |
| 0:19 | Undo | Undo takes the 5 back out. |
| 0:21 | Pencil mode | Bottom-right cell selected, pencil key on; the keypad's digits switch to note weight. |
| 0:24–0:31 | Notes | Three corner notes appear in the cell, one by one. |
| 0:31 | Pencil off | The keypad returns to full digits. |
| 0:34 | Deselect | The cell is let go, and **both ornaments recede**: back to zero chrome. The notes stay. |
| 0:36 | New Game → Steady | A new board in another band, composed from the New Game menu's action. |
| 0:39 | Near the end | The board filled to one cell short (staging, so a whole solve does not take 10 minutes). |
| 0:41 | Last cell | The last empty cell selected, keypad up. |
| 0:44 | Last digit (lag) | The final digit has been entered; the frame has not caught up. |
| 0:46–0:59 | **Solved** | The finished board, with the bottom ornament the only chrome left. The board has **risen toward the viewer**: compare its size with 0:41. |
| 0:59 | SharePlay co-solve | `--vision-coplay-demo`: the same board, recomposed from its seed, joined by one ghost participant (no FaceTime call can reach a simulator). |
| 1:02–1:19 | Another hand | The ghost's digits land in **its tint (gold)**, `DuelTint`'s partner of your accent, one every 2.5 s, never in your selected cell. |
| 1:19–1:28 | Solve, motion on | `--vision-solve` with Reduce Motion off: the solved board rises (from 1:22). |
| 1:28–1:37 | **Solve, Reduce Motion on** | The same solve with Reduce Motion on: the board **does not rise**. |
| 1:37 | Side by side | Motion on (left) and Reduce Motion on (right), a few seconds after the solve. |

## Not shown, and why

- **Gaze / hover highlight.** It is rendered by the system, out of process, from
  where the eyes rest, and the app never learns where that is. A simulator shows
  it under the pointer, and no pointer could be moved here.
- **The pinch itself** (and pinch-and-drag). Every interaction is the model call
  a pinch makes, not a pinch. See above.
- **Moving the window (grab).** The window bar belongs to the system, and
  dragging it needs input that could not be injected.
- **The New Game menu, open.** The band was picked through the menu's action
  (`compose(.steady)`); the open menu itself was never drawn.
- **The Afterglow wave and the spark burst.** Both are over in about a second,
  and a simulator screenshot here took several. No frame caught either. The
  lift, which holds, did show, and so did its absence under Reduce Motion.
  Whether Reduce Motion removes the sparks is the same `reduceMotion ? nil`
  branch that removes the lift (`VisionBoardScreen.swift`), but it was not seen.
- **Reduce Motion through Settings ▸ Accessibility.** It was set with
  `defaults write com.apple.Accessibility ReduceMotionEnabled`, then the app
  relaunched. Settings could not be driven.
- **VoiceOver navigating cells.** Not shown at all. VoiceOver needs input to
  move between elements, and there was none. The 81-element tree is the shipped
  `BoardAccessibility`, unchanged, but on visionOS it was not exercised here.
- **Real eye tracking, real hands, Personas, a real SharePlay call, Game Center
  sign-in, CloudKit sync.** A simulator has none of them. (Game Center's own
  sign-in window *was* seen during development, which is why the headset no
  longer authenticates until asked; see `nine/DEVIATIONS.md`.)

## Reproducing

```bash
U=8ED61F7C-F416-4459-83FE-76398896B77B
xcrun simctl launch $U com.couchsuite.nine --vision-wait-go --vision-tour
# once the board is drawn, each of these advances one step:
touch "$(xcrun simctl get_app_container $U com.couchsuite.nine data)/tmp/vision-go"
```

Without `--vision-wait-go` the tour runs on timers, about 45 s once the window
is up.
