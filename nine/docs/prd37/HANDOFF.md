# PRD-37 handoff — continuing without the owner at the keyboard

State on 2026-10-15, written for a fresh session that has none of the previous
session's context. Read this whole file before acting.

## Where things are

- **Repo / worktree:** `/Users/aquilops/nine`, branch `claude/nine-duo-prd37`,
  pushed. Draft PR: https://github.com/ngoldbla/nine/pull/61 (base `main`).
- **Read first, in order:** `CLAUDE.md` (repo root), `nine/PRD-37.md` (the spec;
  §1 is measured Duo geometry), the PRD-37 section at the end of
  `nine/DEVIATIONS.md`, `nine/docs/prd37/execution-ledger.md` (every task,
  test result and ruling so far), `nine/docs/prd37/README.md`.
- **Plan that was executed:** `nine/docs/superpowers/plans/2026-10-14-prd37-the-spread.md`
  (Tasks 0–11 complete, plus a final-review fix pass, commit `996ddc9`).
- **Gate (must stay green):** `cd nine && swift test`; `cd couchkit && swift test`;
  `cd nine && python3 scripts/strings.py --selftest-catalog && python3 scripts/strings.py --audit` (0 new).

## Machine facts that will otherwise cost you hours

- Two Xcodes. `/Applications/Xcode.app` is **26.6 and stays `xcode-select`'s
  default** (other agents share this Mac). For anything iOS 27.1 / Duo, prefix
  `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer`.
- **Build unsigned, always:** `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.
  A signed macOS Debug build hangs on a keychain prompt for the Distribution
  identity, and the owner must be asked before anything touches signing.
- The four builds to run after any app change (iOS/tvOS/macOS on 26.6, iOS on 27.1):
  regenerate with `cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate`, then
  `xcodebuild -project Nine.xcodeproj -scheme Nine -destination '<dest>' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
  for `generic/platform=iOS Simulator`, `generic/platform=tvOS Simulator`,
  `platform=macOS`, and the 27.1 iOS build into `-derivedDataPath build271`.
  Each takes minutes on this machine; run them in the background.
- **The iOS 27.1 simulator runtime runs only `iPhone Duo`.** iPhone/iPad lanes
  pin iOS 26.5 (`simrig.IPHONE_RUNTIME`).
- **Simulators you own** (created by this work; you may boot, erase, reboot them):
  `Nine-Duo-Probe` 5B8C0158-1D1D-4893-AD33-C669512D1100 (iOS 27.1, slimmed,
  keeps `com.apple.gamed`, **left booted in the Open posture — keep it booted**:
  posture can only be changed by a person in Device Hub), `Nine-AX`
  F2A2C95F-0F65-48BA-B2A0-8B3AC32E197F, `Nine-Shotlist-iPhone`
  94DC78C7-DDC8-47C2-9781-71FEA7D16154, `Nine-Shotlist-iPad`
  256B4FEA-6221-4134-90AB-AF51F1E33699, `Nine-Contrast`, `Nine-Loc`. Any other
  booted simulator belongs to someone else: leave it alone. Erased/created
  simulators come up stock — re-slim with `simslim on <udid> --keep com.apple.gamed`
  (Nine waits on Game Center at launch), except baseline lanes, which run stock
  (`NINE_SIMSLIM=0`) to match CI.
- **Open-Duo limits:** `sim-use describe-ui` cannot read the open Duo's inner
  panel and `sim-use tap` does not reach it (Apple 187148389). Screenshot the
  inner panel with `xcrun simctl io <udid> screenshot --display=primary-1`
  (the default `primary` is the dark outer panel).
- **Stale touch:** on long harness runs the iPhone simulator's touch input goes
  stale (`sim-use tap` reports success, nothing happens — hits `main` and the
  branch alike). A simulator reboot fixes it. Do not mistake it for a regression.
- **Zero-change proof method:** compare `main` vs branch built with the *same*
  Xcode, on iOS 26.5, through the same harness, with `--out-dir` per run.
  Committed AX baselines differ from both only by the `sim-use` version header
  (0.11.0 → v0.12.0) and a History-sheet difference `main` shows too — do not
  re-record them. Reference scripts: `nine/docs/prd37/scripts/proof*.sh`
  (bash, not zsh — zsh `local a=1 b=$a` silently broke an earlier run).

## What to do, in order

1. **The five deferred minors from the final review** (ledger, "minor (deferred)"):
   - `simrig.prepare_simulator` slims fresh iPhone baseline simulators by
     default; make baseline lanes pass `slim=False` (only Duo lanes slim), and
     give `reslim` `--preserve-boot-state`.
   - Publish `\.couchPanelWidth` only when the fold also yields a spread
     (`FoldRules.spread != nil` for the root size) — add a pure test.
   - `FoldProbe` writes `@State` on every resize even with no band; store the
     width only when a band validates.
   - Reword the stale `.readsFold()` comment in `NineApp.swift`.
   - `shotlist.py` `index.json`: record the runtime per device.
2. **Harness robustness:** have `simrig` recover from stale touch — when a
   `wait_for` after a tap times out, reboot the simulator once and retry the
   scene. Prove it by running `ax-snapshot.py --runtime 26.5` twice in a row.
3. **Photograph every open-Duo surface without taps.** Add DEBUG-only launch
   arguments (e.g. `-NineDebugSurface prefs|history|boards|tutorial|school|coach`)
   under `#if DEBUG`, reached through `simrig.relaunch(..., args=...)`, and add
   those scenes to `shotlist.py`'s `DUO_SCENES` for `duo-open`. Rules:
   compiled out of Release; with no argument, Debug behaviour is byte-for-byte
   today's (prove with the AX lane, main vs branch, both toolchains); no new
   user-facing strings. Then run `shotlist.py --device duo-open` — it prompts for
   the posture: the Duo is already Open, answer from the script's stdin
   (`printf 'open\n' | ...` works because `require_posture` reads stdin — if it
   refuses a non-TTY, use a pty via `script -q /dev/null`), and **look at every
   screenshot** against PRD-37 §4.4. Fix what is wrong, re-photograph, commit
   the downscaled screens to `nine/docs/prd37/screens/`.
4. **Re-run the zero-change proof** after the code changes (AX on 26.6 and 27.1,
   loc on 27.1, contrast gate) and update the numbers in DEVIATIONS and the PR.
5. **Record and push:** ledger lines for every task and ruling, DEVIATIONS,
   PRD-37 status, the PR body (keep the open-items list honest), commit with
   author `70771914+ngoldbla@users.noreply.github.com` (already configured) and
   the `Co-Authored-By` trailer, push to `claude/nine-duo-prd37`.

## Still needs the owner (do not attempt; list them in the PR)

Bending/flattening/folding the Duo, the rose on a bent Duo, the coach card's
drag, folding mid-game, and the first `duo-folded` baselines (posture Closed).

## Decisions

The owner asked not to be consulted: when a choice comes up, pick the option
that keeps **zero change on every non-Duo device**, the covenant in
`nine/docs/EXECUTING-A-PRD.md` §1 (no new input concepts beyond the coach drag,
no new persisted state, no new strings), and the spec; record it in the ledger
as `Ruling: <decision> — <why> — <cost if wrong>` and keep going.

**Hard stops — do not do these, even to keep going:** anything touching code
signing, certificates, match or App Store Connect; any fastlane
`release`/`store_*`/`beta`/`match` lane; changing `MARKETING_VERSION`;
merging the PR or marking it ready for review; force-pushing or rewriting
pushed history; rebooting or erasing a simulator not listed above; deleting
anything you did not create.
