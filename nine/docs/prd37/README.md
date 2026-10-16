# PRD-37 working record

What the iPhone Duo work was measured, decided and verified with, kept so the
evidence behind [PRD-37](../../PRD-37.md) and the PRD-37 section of
[DEVIATIONS](../../DEVIATIONS.md) survives the session that produced it.
Nothing here is built, shipped or run by CI.

| Path | What it is |
|---|---|
| `probe/DuoProbe.swift` | The measurement app every number in PRD-37 §1 came from. It logs window size, safe area, size classes, hinge state and the `.division` / `.occlusion` reserved regions on every change. Launched with the argument `split` or `overlay` it hosts Apple's `ArrangementView` and logs where it puts each pane (PRD-37 §1.5). Built with `swiftc -parse-as-library -target arm64-apple-ios27.1-simulator` into a hand-made `.app` with Xcode 27.1. |
| `logs/probe-default.log` | The probe through closed → open → partially open → closed. |
| `logs/probe-arrangementview-split.log` | Apple's split arrangement through the same postures. |
| `mockup/duo-layouts.html` | The interactive mockup the owner chose the layout from (every surface, folded / flat / bent, today vs proposed). Open it in a browser. Its 557pt board predates the 44pt-key constraint; the shipped board is 550.5pt. |
| `screens/` | Downscaled (1000px) captures, all from the iOS 27.1 simulator: the probe folded and open; Apple's split flat and bent; today's build folded and open (the defect); the spread's game screen and first run (the fix). |
| `scripts/` | The throwaway drivers used for verification, kept as they ran (paths point at the session's scratchpad): `duo_session.py` (install, seed, photograph both panels), `watch-duo.sh` / `watch-shots.sh` (photograph on a timer / on each hinge change), `proof.sh` / `proof-ax.sh` (main vs branch through the AX, contrast and loc lanes), `rose_rate.py` (the stale-touch diagnosis), `visual_diff.py` (main vs branch pixel diff). |
| `execution-ledger.md` | The task-by-task ledger: each task's commits and test result, every ruling made during execution with what it costs if wrong, the final review's findings and the deferred minors. |
