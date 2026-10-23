# Nine on Vision Pro — SharePlay co-solve test script

A manual script for the one thing no simulator can do: a real SharePlay call.
`CoSolveTests` already proves convergence of the per-cell register; this proves
the call around it. Written before the first live run so the run can be judged
against it rather than described after it.

## Setup

You need **two participants** in a FaceTime call, each with Nine installed from
the same build:

| Rig | A | B |
|---|---|---|
| Preferred | Vision Pro (headset A) | Vision Pro (headset B) |
| Acceptable | Vision Pro | a Mac or iPhone in the same FaceTime call, only to supply a second Persona-less participant — **B cannot run Nine** (the co-solve is visionOS-only), so steps marked **B** need a second headset |

Both headsets: signed in to **different** Apple Accounts (SharePlay needs two
people), Nine at the same build number, Settings ▸ Accessibility ▸ Reduce Motion
**off**. Clear the board on both: New Game ▸ Gentle.

Record each step's result in the table at the end, with a screenshot or a short
screen recording from the headset (Control Center ▸ Record My View).

## Steps

### 1. Join

1. A: pinch any empty cell so the bottom ornament appears. Pinch **Play
   together** (the SharePlay glyph) and share into the FaceTime call.
2. B: accept the SharePlay invitation.

**Expect**
- B's board is recomposed to **A's board** (same givens) before any digit
  arrives. B's previous board is still in B's library afterwards.
- Both windows use the **side-by-side** template: each Persona stands on the
  same side of one board.
- The bottom ornament on both shows the "solving together" state with a count
  of **2**, and a **Leave** button.

### 2. A late joiner gets the snapshot

1. A: place three correct digits before B accepts (repeat step 1 with B joining
   late, or have a third headset C join after moves have been made).
2. B (or C) joins.

**Expect**
- The late joiner sees **all three digits**, tinted as somebody else's, within
  a couple of seconds of joining — sent by `CoSolveSnapshot` on the roster
  change, not by the next move.
- Digits the late joiner had on its own board before joining are not on the
  shared board (it recomposed from the invite).

### 3. Concurrent writes to one cell converge

1. A and B select the **same empty cell**.
2. On a count of three, both pinch a **different** digit at the same moment.
   Repeat five times on five cells.

**Expect**
- After each round, **both boards show the same digit** in that cell. Which
  digit wins is not specified; that both agree is.
- The winning digit's tint matches its author on both boards (yours in your
  accent, theirs in `DuelTint`'s partner colour).

### 4. Undo takes back only your own moves

1. A places a digit; B places a digit elsewhere.
2. A pinches **Undo** on the keypad.

**Expect**
- A's digit is removed on **both** boards. B's digit stays.
- If B had overwritten A's last digit, A's undo skips it and takes back A's
  move before that.
- Undo is greyed for A once A has nothing standing to take back.

### 5. Leaving keeps your board

1. B pinches **Leave** in the bottom ornament (or ends SharePlay from the system
   control).

**Expect**
- B keeps the shared board **as it stood**, digits and tints included, and can
  keep solving alone.
- A sees the count drop to **1**, keeps the board, and keeps solving.
- Relaunch Nine on B: the board reopens with **the tints still there**
  (`nine.vision.cosolve`).

### 6. A shared solve is nobody's

1. Rejoin (step 1) and finish a board together.

**Expect**
- Both boards show the solve (Afterglow, the lift) and are marked solved in the
  library.
- **No** new record in Stats on the phone signed into A's or B's account
  (`nine.history` unchanged), and **no** Game Center leaderboard submission
  or achievement for either.
- The phone signed into A's account **does** get the board's comet and debrief
  (a replay is the board's, by the duel rule).
- A board solved **after** B has left, with B's digits still on it, is still
  nobody's solve.

## Results

| Step | Build | A | B | Pass/fail | Evidence | Notes |
|---|---|---|---|---|---|---|
| 1 Join | | | | | | |
| 2 Late joiner | | | | | | |
| 3 Convergence | | | | | | |
| 4 Undo | | | | | | |
| 5 Leave | | | | | | |
| 6 Nobody's solve | | | | | | |
