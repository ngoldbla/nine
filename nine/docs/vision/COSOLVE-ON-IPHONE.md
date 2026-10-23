# Should iPhone and iPad join a co-solve? — the trade-off

Status: **proposal, not built.** Asked for in the Vision follow-through
(item 7) as "bring me the trade-off before building".

## What exists today

| | iPhone / iPad | Vision Pro |
|---|---|---|
| Activity | `com.couchsuite.nine.parlor` (`NineParlorActivity`) | `com.couchsuite.nine.cosolve` (`NineCoSolveActivity`) |
| Shape | **Parlor**: same board, everyone on their *own* copy, times revealed together at the end (PRD-28) | **Co-solve**: *one* board, everyone's hands on it |
| Wire | `ParlorEnvelope` (presence, fill, finish) | `ParlorEnvelope` + `CoSolveMove` + `CoSolveSnapshot` |
| History / Game Center | each player's own solve counts | nobody's solve |

The activity identifiers are different on purpose (DEVIATIONS, "SharePlay is a
co-solve, a third shape"): a phone that answered the headset's invitation with a
parlor would race a board the headset is sharing.

## Option A — leave it headset-only (today)

- **For:** no new input concept on iOS this release (EXECUTING-A-PRD §1: one per
  release, and iOS 1.2's is already spent). The parlor stays the iPhone's
  SharePlay, which matches how people use a phone on a FaceTime call: each on
  their own screen, racing gently.
- **Against:** a headset owner cannot co-solve with a friend who has only a
  phone, which is most friends. The Vision SharePlay button only works with
  another Vision Pro.

## Option B — iPhone/iPad join the co-solve as a second activity

`GroupActivity` on iOS registering `NineCoSolveActivity` too, reusing
`Sources/Shared/CoSolve.swift` (ledger, moves, snapshot, own-move undo — all
pure and already tested) and the transport shape in `VisionCoSolve.swift`.

- **Code:** `VisionCoSolve` is ~300 lines, about half of it portable as is
  (the session, the transport). The rest is the model seam, which on iOS means
  `AppModel` — the board, the undo, the solve path, `isDuel`-style
  "nobody's solve" — touching `TouchUI.swift`, the contention file
  (EXECUTING-A-PRD §7). Estimate: 2–3 days including the AX baselines and
  localization harness re-records.
- **Product:** the phone then has **two** SharePlay modes. The shelf's "Play
  together" has to ask which, or infer it from who started the call — a new
  decision on the 11pm-in-bed path, which the taste ritual will push back on.
- **Tints:** two seats today ("you" and "everyone else"); a phone joining makes
  three-person calls ordinary, and `DuelTint` proves separation for two.
- **Risk:** the parlor and the co-solve share `ParlorSession` for the roster;
  running both on one device means two sessions' rosters in one process, which
  nothing has tested.

## Option C — iPhone/iPad answer the headset's invitation only

No "start a co-solve" on the phone at all; a phone in the call can *accept* the
headset's co-solve (it opens the shared board), and its own "Play together"
stays the parlor.

- **For:** no new decision on the phone's shelf; the input concept is "a call
  from a headset puts you on its board", which arrives from outside the app.
  Most of Option B's code, none of its product cost.
- **Against:** still `AppModel` work in the contention file; still needs the
  three-seat tint question answered (cap the co-solve at two hands? tint by
  "you / not you" as now?).

## Recommendation

**C, after the headset's co-solve has had one real two-headset run**
(`SHAREPLAY-TEST.md`). The ledger is proven in tests, but nothing yet proves the
call around it, and porting an unproven shape to the platform with the most
players doubles the surface the first live bug lands on. Keep "two seats: you
and everyone else" for C; revisit per-person tints only if real calls show
people want to know *who* placed a digit.
