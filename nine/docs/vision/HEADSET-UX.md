# Nine on Vision Pro — headset UX: findings and proposals

Items 8–15 of the Vision follow-through. Most of them are a decision or a
device check rather than code; this file holds each one's state so the next
person starts from it rather than from the prompt. **Proposals here are not
built** unless the line says so.

## 8. Game Center — device only

Nothing to change until a signed-in headset has been seen. On a real Vision Pro,
signed in to Game Center in Settings:

1. Fresh install, launch, do **not** pinch the Game Center button. Expected
   today: no Game Center UI at all (the headset does not authenticate until
   asked, `nine.vision.gameCenter`).
2. Pinch it. Expected: the dashboard (already signed in), no sign-in sheet.
3. Solve a Gentle board. Expected: a leaderboard entry and any first-solve
   achievement, visible from the phone's Game Center too.
4. Relaunch. Expected: authenticates silently; still no UI.

**If step 2 shows no sign-in sheet on a signed-in headset**, the "authenticate
only after the first pinch" rule costs nothing to drop for signed-in players
but still matters for signed-out ones — and the app cannot tell which it is
before calling `authenticate()`. So the rule stays unless step 1 on a
*signed-out* headset also shows nothing, which the simulator says it does not.

## 9. Board switching after a merge — proposal: a quiet offer, not a jump

Today an idle headset (no cell selected) jumps to the newest classic board
another device has moved past (`HeadsetBoards.newerBoard`). A board changing
under someone who was just looking at it, with nothing on screen saying why, is
the one surprise this platform cannot afford: the window is in their room.

**Proposed:** keep the board; offer the other one in the bottom ornament, which
is transient and already where boards come from (New Game):

```
[ ⊞ New Game ]  [ ⟳ Continue from iPhone ]  [ ⧉ ]  [ 🎮 ]
```

- Appears only with the ornament (a pinch on a cell), so the idle board stays
  zero-chrome. No badge, no dot, no toast.
- One tap switches; the offer disappears once taken, or once the other board is
  solved or older than this one (`newerBoard` already answers that).
- "from iPhone" needs the source device, which `SyncedEntry` does not carry.
  Without it the label is "Continue your other board". Adding a device name
  is a CloudKit record field — schema change, human gate — so not proposed.
- Still a silent switch when the current board is **solved** or **gone**: there
  is nothing to keep.

Mocked in the session's message (not built). The rule half is ready:
`HeadsetBoards.newerBoard` returns the candidate; the model would publish it as
`offeredBoard` instead of opening it.

**Built (2026-10-23)** as mocked, label "Continue your other board"; see
DEVIATIONS, "Vision Pro follow-through 5".

## 10. Choosing a board — proposal: the same ornament, one level deeper

The smallest surface that fits "one board floating in a room" is not a new
window or a sheet: it is the **New Game menu** grown one section.

```
New Game ▸   Gentle · Steady · Sharp · Fiendish · Nocturne
             ───────────────
In progress  Steady · 34 left · iPhone, 2 h ago
             Sharp · 51 left · 3 days ago
```

- Uses the menu the player already opens to change boards, so no new input
  concept (EXECUTING-A-PRD §1).
- In-progress classic boards only (`HeadsetBoards.isPlayable`), newest first,
  capped at five. History and stats stay on the phone: the headset is for the
  board in front of you.
- Rejected: a leading ornament (always-visible chrome, against rule one); a
  sheet (covers the board, which is the only thing in the room); a second
  window (a library window floating beside a board is two things to place).

**Built (2026-10-23)** as mocked, without the device name ("iPhone, 2 h
ago" is "2 hr. ago"); see DEVIATIONS, "Vision Pro follow-through 5".

## 11. Window size and scale — evaluated, not changed

| Card (pt) | Board side | Cell | Keypad digit | Tool key | ≥ 60 pt? |
|---|---|---|---|---|---|
| 776 (today) | 720 | 80 | 76 | 60.8 | yes |
| 596 (smallest legal) | 540 | 60 | 76 | 60.8 | yes, exactly |
| 1,136 | 1,080 | 120 | 76 | 60.8 | yes |

- The board scales off `VisionBoardMetrics.side`, so a resizable window is a
  `GeometryReader` and `.windowResizability(.contentMinSize)` away. The floor
  is **540 pt of board** (60 pt cells); below it eye targets break.
- Do **not** scale the keypad with the board: it is an ornament at a fixed
  76 pt, which is the right size at every distance the system places it.
- Distance-aware sizing (bigger as the window is pushed back) is what visionOS
  already does: windows keep their angular size as they move away. An app
  doing it again would double the effect. Not proposed.
- **Recommendation:** allow resizing with a 596 pt minimum card. Small enough
  to sit on a desk; the default stays 776.

## 12. Motion and Reduce Motion — device only, plus one code change

The Afterglow wave and the spark burst are over in about a second and no
simulator frame has caught either (`SHOTLIST.md`). On a device:

1. Solve with Reduce Motion off: the wave crosses the board from the winning
   cell, sparks leave the glass and hang, the board rises ~48 pt.
2. Solve with Reduce Motion on: no rise and **no sparks**.

Changed this session: the sparks' `RealityView` is now mounted only for a
solve it will burst for, and never under Reduce Motion — so (2) is structural
rather than a `nil` trigger into a view that was still built. Not yet seen on
a device. `vision-storyboard.py --args --vision-solve` bursts frames after the
solve if a simulator ever draws fast enough to catch it.

## 13. Themes on glass

The headset draws every theme's board plane on visionOS's dark glass
(`isLight` is true only for a theme that pins light: Paper and Camel). The
risk is the two light themes: dark ink on a light plane wash over a dark,
see-through slab. A contrast pass needs composited pixels, not constants —
the iOS lane learned that (`contrast-harness.py` samples screenshots).

Added for it: DEBUG `--vision-theme <raw> [--vision-accent <raw>]` stages the
appearance a phone would have published, because a simulator without an iCloud
account never receives `SharedAppearance`. The pass is nine launches of:

```bash
python3 nine/scripts/vision-storyboard.py --no-build --args --vision-near-solve --vision-theme camel
```

**Proposal pending that pass:** if Paper or Camel fail 4.5:1 for givens against
the composited plane, map them to their dark leaning on this platform only
(Paper → Void, Camel → its own dark tones), the way `auto` already follows the
system. The seven dark themes are expected to pass: their ground is already
dark and the glass only darkens it further.

## 14. Accessibility on visionOS — blocked on tooling

`sim-use describe-ui` against the visionOS simulator timed out waiting for its
daemon socket (`/tmp/sim-use-501/<udid>.sock`) on this host; whether it can
read a visionOS tree at all is not established. The tree itself is
`BoardAccessibility` unchanged (81 cells in 9 boxes), and VoiceOver, Switch
Control and Pointer Control on visionOS need a device. Device script:

1. VoiceOver on: swipe through one box — nine cells, each "Row r, column c,
   empty/digit", then the next box.
2. Rotor actions on a cell: Place 1–9, Note 1–9, Erase (Erase last in the
   rotor — UIKit reverses declaration order).
3. The keypad ornament and the bottom ornament reachable by swipe after the
   board.
4. Switch Control: group scan lands on boxes, then cells.
5. Pointer Control: every cell and key is a target.

Compare against `Tests/AXBaselines/game.txt` (iOS).

## 15. Sound and spatial audio

Sound is deferred suite-wide (DEVIATIONS). Spatial audio on the headset — a
placement tick at the cell, the solve chord from the winning cell — is a
**different proposal**, not part of that deferral: on a headset the board has
a position in the room, and sound from it is how a player who looked away
knows somebody else just placed a digit in a co-solve. Not added; to be
proposed separately with the co-solve, where it would earn its place.
