Build two Nine on Vision Pro surfaces: the board-switch offer (item 9) and the
board chooser (item 10). Both are proposed and mocked in
nine/docs/vision/HEADSET-UX.md; the user has approved building them as mocked.

Read first: CLAUDE.md, nine/docs/EXECUTING-A-PRD.md, the "Vision Pro" section
of BUILD.md, the last four "Vision Pro follow-through" entries at the end of
nine/DEVIATIONS.md, and nine/docs/vision/HEADSET-UX.md items 9 and 10. Use the
visionOS skills: visionos-design-guidelines, visionos.

Where things stand (nine/release-staging, pushed at 44db982 or later):
- `Sources/Shared/HeadsetBoards.swift` holds the headset's board rules, tested
  under `swift test` (`Tests/SharedTests/HeadsetBoardsTests.swift`):
  `isPlayable` (classic only — channel rules do not sync), `atLaunch`,
  `newerBoard(in:current:)`, `migrate`.
- `VisionModel.refreshAfterMerge` currently **opens** `newerBoard` silently
  when the player is idle (no cell selected). Item 9 replaces that.
- The bottom ornament is `BoardActions` in
  `Sources/Vision/VisionBoardScreen.swift`: New Game (a `Menu` of bands),
  Play together / the co-solve state, Game Center. It shows when a cell is
  selected, on a solved board, and for the whole of a co-solve.

## 9. The board-switch offer

- After a merge, if `newerBoard` has a candidate, publish it as
  `VisionModel.offeredBoard` instead of opening it. Keep the silent switch
  only when the current board is solved or gone (nothing to keep) — put that
  decision in `HeadsetBoards` as a pure function with tests first.
- The bottom ornament shows "Continue your other board" (one button) while
  there is an offer. No badge, dot, toast or auto-shown chrome on an idle
  board: README rule one, zero visible UI at rest.
- Taking the offer opens the board and clears the offer. The offer also
  clears when the candidate is solved, removed, or becomes older than the
  current board (re-evaluate on every merge).
- Off during a co-solve, like the switch it replaces.
- No device name: `SyncedEntry` does not carry one, and adding it is a
  CloudKit schema change (human gate). Do not add it.

## 10. The board chooser

- An "In progress" section in the New Game menu, below the bands: classic
  in-progress boards (`isPlayable`), newest first, at most five, the current
  board excluded. Each row: band and cells left, plus a relative time
  ("2 h ago"). Selecting one opens it.
- The row list is a pure function in `HeadsetBoards` with tests (filtering,
  order, cap, exclusion). Relative-time formatting stays in the view.
- No new window, sheet or ornament.

## Rules that will bite

- New strings: add each to `EnglishPhrases.table`, a translator comment to
  `COMMENTS` in `nine/scripts/strings.py`, then
  `python3 scripts/strings.py --build-catalog`, then add the nine
  translations as `needs_review` (de es fr it ja ko nl pt-BR zh-Hans). Reuse
  existing keys where one fits.
- `VisionSealTests` must stay green: never pull `AppModel` into NineVision,
  keep every DEBUG staging argument inside `#if DEBUG`.
- Per-board persisted state goes in a sibling key, never a field on
  `LibraryEntry` (EXECUTING-A-PRD §2). The offer is not persisted.
- This host is an 8 GB Mac that is often heavily loaded: run builds and
  `swift test` sequentially, in the background, not in parallel.

## Verification

- The PR gate: `cd nine && swift test`, `cd couchkit && swift test`,
  `python3 scripts/strings.py --selftest-catalog`, `--audit`.
- `xcodebuild` for iOS, tvOS, macOS and NineVision (simulator, Debug and
  Release), as in `.github/workflows/nine-vision.yml`.
- Screenshots on the "Nine Vision" simulator
  (8ED61F7C-F416-4459-83FE-76398896B77B) of the ornament with the offer and
  of the open New Game menu. No input reaches this simulator from a script,
  so stage both with new DEBUG launch arguments (e.g. `--vision-offer-demo`,
  `--vision-chooser-demo`, sealed in `VisionSealTests` and in the CI Release
  leak check). Use `nine/scripts/vision-storyboard.py` (staging arguments
  after `--`); the app signals its window is up by consuming the first
  `vision-go`. A visionOS `Menu` may not render open from a model call —
  if it cannot be shown, say so and screenshot what can be.
- Record what was built and what was not in nine/DEVIATIONS.md, and say
  plainly what only a real headset can confirm.

Commit on nine/release-staging, one commit per item, and push.
