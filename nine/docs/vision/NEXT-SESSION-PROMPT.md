Continue the Nine visionOS port: function, UX and the scaffolding around it.
Read CLAUDE.md, nine/docs/EXECUTING-A-PRD.md, the "Vision Pro" section of
BUILD.md, the "Vision Pro parity" entry at the end of nine/DEVIATIONS.md and
nine/docs/vision/SHOTLIST.md first. Use the visionOS skills:
visionos-design-guidelines, visionos, realitykit-visionos-developer.

Where things stand (nine/release-staging):
- 4c52f0a added the `NineVision` target; 49ee519 gave it parity (CloudKit
  library via `LibraryCloudStore`/`LibrarySync`, `nine.history` + Game Center,
  KVS `SharedAppearance`, SharePlay co-solve over `CoSolveMove`); 6e709d8 added
  the DEBUG `--vision-tour` / `--vision-wait-go` staging and the walkthrough.
- `VisionSealTests` fails if NineVision compiles the CloudKit store without a
  CloudKit entitlement, or ever pulls in `AppModel`. Keep it green.
- Known limits of this machine (see memory "vision-sim-no-input"): the
  simulator control tool cannot inject input into a visionOS simulator
  (`dtuhidServiceNotVended`), Xcode 27 has no Simulator.app (only Device Hub),
  and `simctl io recordVideo` starves the simulator. Drive the app with DEBUG
  launch arguments and screenshots. Ask me before using Device Hub through
  computer-use, and ask me for anything that needs a real Vision Pro or an
  Apple Account (I sign in; you never enter credentials).

Work through these in order, one commit per numbered group, and record every
deferral in nine/DEVIATIONS.md with its reason.

## 1. Correctness that crosses platforms

1. `nine.history` merge on every writer. Only Vision Pro merges the live KVS
   copy before writing (`SolveHistory.merged`). `AppModel` on iPhone, Apple TV
   and Mac writes its local copy over KVS, which can drop a headset's solve.
   Make every writer merge, and pick up `didChangeExternallyNotification`.
   Check `nine.channels` for the same problem. Tests first; this touches
   `AppModel`, so keep the change small and measured against the 800 ms launch
   budget (EXECUTING-A-PRD §2).
2. The `CKContainer` trap on unsigned builds. A `CODE_SIGNING_ALLOWED=NO`
   simulator build has no entitlements, so with an iCloud account signed in
   it traps on the first `LibraryCloudStore()`. iOS has the same exposure
   (`mayBuildCloudContainer` is `true` off macOS). Find a guard that reads
   the binary's real entitlements on iOS-family platforms, or document why
   none exists, and cover it in `VisionSealTests`.
3. Replays from Vision solves. The headset mints no `SolveReplay`, so a board
   finished on Vision Pro has no comet or debrief on the phone. Mint it on
   the solve path (pure Engine code) and push it through the same store. Keep
   `onRemoteReplay` unset unless the headset gains a surface for it.
4. Variant (channel) boards. `mostRecentFreePartial` keeps the headset on
   classic boards, but a channel board arriving by CloudKit or a co-solve
   invite would draw without its `channelRules`. Either pass the rules through
   or filter explicitly, with a test.

## 2. Proving sync and SharePlay

5. CloudKit sync on simulators. Create a fresh iPhone simulator
   (`Nine-Sync-iPhone`) and slim it with `simslim on <udid> --except icloud`.
   Tell me when it is up; I sign the same Apple Account into it and into
   "Nine Vision". Then start a board on the iPhone, finish it in the visionOS
   simulator, and show the iPhone receiving the solve. Keep the screenshots.
6. A real SharePlay co-solve (needs me and two devices, or a headset and a
   FaceTime call). Write the test script first: join, a late joiner gets the
   snapshot, concurrent writes to one cell converge, leaving keeps your board,
   no history or Game Center for a shared solve.
7. Co-solve gaps to close:
   - Undo of your own moves only. It is off today because `NineGame.undoStack`
     is shared; consider an undo built on the `CoSolveLedger`.
   - Persist the seat attribution for the board (a sibling key keyed by board
     id, like `nine.duel`), so tints survive a relaunch.
   - A visible "Leave" and a clear "you are solving together" state; the
     participant count is the only signal today.
   - Decide whether iPhone/iPad should join a co-solve too (a `GroupActivity`
     on iOS, reusing `CoSolve.swift`). Bring me the trade-off before building.

## 3. UX on the headset

8. Game Center. Verify sign-in, leaderboard submission and achievements on a
   real Vision Pro. Revisit the "authenticate only after the first pinch"
   choice once we know whether a signed-in headset ever shows UI.
9. Board switching. After a merge, an idle headset jumps to the newest
   in-progress board. Decide whether that should be a gentle offer ("continue
   your board from iPhone") instead of a silent switch. Mock it first; the
   covenant's zero-chrome rule applies.
10. No way to choose a board. The headset opens one board; there is no
    library, history or stats surface. Propose the smallest surface that fits
    "one board floating in a room" (a leading ornament? a sheet?) before
    building it.
11. Window and scale. The window is a fixed 776 pt square with
    `.contentSize` resizability. Evaluate letting the player resize it (the
    board scales off `side`), and whether a distance-aware size helps
    legibility. Check the 60 pt eye-target floor at every size.
12. Motion and Reduce Motion. On a device, confirm the Afterglow wave, the
    spark burst and the lift, and that Reduce Motion removes the sparks as
    well as the lift. No simulator frame caught the wave or the sparks.
13. Themes on glass. Light and tinted themes (`camel`, `blueprint`, …) now
    draw on visionOS's dark glass. Run a contrast pass on each theme and
    decide whether some should map to their dark leaning on this platform.
14. Accessibility on visionOS. VoiceOver walking the 81-cell tree, the
    keypad and both ornaments, plus Switch Control and Pointer Control. None
    of it has been exercised on visionOS. Capture the tree and compare it to
    the iOS baseline.
15. Sound and haptics. Sound is deferred suite-wide (DEVIATIONS); note whether
    spatial audio for placement and solve belongs in that deferral or should
    be proposed separately. Do not add it without asking.

## 4. Scaffolding

16. CI builds NineVision. No workflow does today. Add a `NineVision` build
    (simulator, `CODE_SIGNING_ALLOWED=NO`) to the PR lane, and a Release build
    so DEBUG-only staging cannot leak into Release. Mind the shared-scheme
    rule in CLAUDE.md: NineVision's `scheme: {}` must not hide `Nine`.
17. Testable VisionModel logic. Move the pure decisions out of the
    `@Observable` model into `Sources/Shared` (slot migration, "which board to
    open after a merge", applying a remote co-solve move to a `NineGame` with
    attribution) and test them under `swift test`.
18. Storyboard tooling. Promote the session's capture scripts into
    `nine/scripts/vision-storyboard.py` on top of `simrig.py`: wait for the
    first frame by luminance, step with `vision-go`, burst after a solve,
    assemble with ffmpeg. Also extend `simrig.py` with a visionOS runtime and
    device, and teach `ax-snapshot.py` to dump the visionOS tree if the AX API
    reaches it.
19. Launch performance. On a loaded machine the first frame took 30 s to
    several minutes, inside RealityKit scene setup
    (`MRUISharedSimulation.createRealityKitScene` → `swift_conformsToProtocol`).
    Measure Debug against Release, and with and without the `AfterglowSparks`
    `RealityView` mounted at launch. Mount it lazily if it is the cost.
20. Release plumbing.
    - Dry-run `fastlane beta platform:vision upload:false` once `signing.env`
      exists here.
    - Add visionOS to the App Store Connect record (my step; tell me when).
    - Add a `vision` leg to the store lanes (`STORE_PLATFORMS`,
      `RELEASE_PLATFORMS`, `store_check` display types) with Vision Pro
      screenshots captured through the storyboard tool.
    - Then set `COUCH_SHIP_VISION=1` in CI.

## Verification for every group

- The PR gate: `cd nine && swift test`, `cd couchkit && swift test`,
  `python3 scripts/strings.py --selftest-catalog`, `--audit`.
- `xcodebuild` for iOS, tvOS, macOS and NineVision (simulator and device,
  plus Release for NineVision).
- Screenshots of every surface you touched on the "Nine Vision" simulator.
- Say plainly what could only be checked on a real headset, and what wasn't
  checked at all.

Commit on nine/release-staging as each group lands.
