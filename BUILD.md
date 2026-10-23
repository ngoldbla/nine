# Building Nine

One universal app plus the CouchKit Swift package it is built on. Engine and
catalog logic is verified by tests that run on any platform, with no Xcode.

## Prerequisites

- macOS with **Xcode 26+** (tvOS 26 / iOS 26 SDKs for Liquid Glass; the app
  deploys back to tvOS 18 / iOS 18 with an automatic material fallback via
  CouchKit's `CouchGlass` shim)
- **XcodeGen** (`brew install xcodegen`) — project files are generated, never
  committed
- Python 3 for the harnesses in `nine/scripts/`

## Build & run

```bash
cd nine
xcodegen generate
open Nine.xcodeproj      # pick a destination, Cmd+R
```

`xcodegen generate` produces four targets:

| Target | Destinations |
|---|---|
| `Nine` | tvOS, iOS (iPhone + iPad), macOS — one universal target |
| `NineWidgets` | iOS app extension (WidgetKit); filtered out of the tvOS and macOS graphs |
| `NineWatch` | watchOS, embedded in the iOS app |
| `NineVision` | visionOS — its own target and shared scheme, same bundle id as `Nine` |

### Vision Pro

`NineVision` is the watch's shape, not the universal target's: a curated source
list (`Sources/Vision` plus the Engine, Shared, Strings, the four board files,
and the CloudKit store, Game Center and parlor seam compiled in on their own)
with its own small model, so `AppModel` never reaches it. It carries
`Nine-visionOS.entitlements` (checked in, like tvOS's) because
`LibraryCloudStore` builds a `CKContainer`; `VisionSealTests` holds that pair
together. It signs with the iOS App Store profile, which Apple mints for
visionOS too, and ships with `fastlane beta platform:vision` (train +3).

```bash
xcodebuild -project Nine.xcodeproj -scheme NineVision \
  -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

A simulator cannot be pinched from a script, so DEBUG builds take two launch
arguments that stage what a screenshot needs: `--vision-near-solve` (every cell
but one filled and selected — the keypad is up) and `--vision-solve` (the same,
then the last digit lands two seconds in, through the pinch's own path).
`--vision-coplay-demo` starts a SharePlay co-solve over a ghost transport that
places a correct digit every 2.5 s, since no FaceTime call reaches a simulator.
`--vision-tour` walks every board interaction (select, place, error, erase,
undo, pencil, deselect, new game, solve) through the model's own input calls,
because the visionOS simulator vends no HID digitizer to inject a pinch with;
add `--vision-wait-go` to advance it one step per `tmp/vision-go` file instead
of on timers. `nine/docs/vision/SHOTLIST.md` is the walkthrough made with them.

The app icon is a `.solidimagestack` in `VisionAssets.xcassets`, **derived** from
`Nine.icon` by `python3 nine/scripts/vision-icon.py` — actool accepts the Icon
Composer document for `xros` and silently emits no icon. Re-run the script after
editing `Nine.icon`. `simslim` does not slim visionOS simulators; they run stock.

Nine depends on `../couchkit` as a local SwiftPM package. There are no other
dependencies and no remote packages anywhere in the repo.

## Verify without Xcode (any platform)

```bash
cd nine     && swift test    # engine + shared, including the golden corpus
cd couchkit && swift test    # CouchCore + the pure half of PadKit

cd nine && python3 scripts/strings.py --selftest-catalog
cd nine && python3 scripts/strings.py --audit
```

These four commands are exactly what `.github/workflows/nine-engine.yml` runs on
every pull request, so a green run locally is a green run in CI.

## The measured gates

`.github/workflows/nine-accessibility.yml` runs the expensive lane on every PR.
It is deliberately separate from the TestFlight workflow: that one ships and must
never be blocked by a slow simulator; this one gates review and is free to be
slow.

| Harness | What it measures |
|---|---|
| `nine/scripts/ax-snapshot.py` | the accessibility tree per screen, diffed against committed baselines |
| `nine/scripts/contrast-harness.py` | contrast sampled from screenshots of the composited glass, not computed from theme constants |
| `nine/scripts/loc-harness.py` | pseudo-localization and RTL, five screens × five locale modes |
| `nine/scripts/shotlist.py` | photographs every surface across iPhone/iPad × light/dark × portrait/landscape. No baselines and no gate by design — a pixel diff of a live-blur material is noise — so it produces evidence and leaves judgement to the reader. |

All four sit on `nine/scripts/simrig.py`: the dedicated simulator, the erase, the
bridge warm-up, the seeded container, the settle-before-you-read discipline.
Every one of those exists because of a specific way the naive version was flaky.

Baselines live beside the harnesses in `nine/Tests/{AXBaselines,ContrastBaselines,LocBaselines}`.
The committed files are the contract; the `.captured/` directories next to them
are what a comparison run actually saw and are gitignored.

## Ship to TestFlight

```bash
echo 'COUCH_TEAM_ID=<your team id>' > signing.env   # gitignored, one-time
bundle install
bundle exec fastlane ios beta_app app:nine upload:false   # dry run, all platforms
```

See [TESTFLIGHT.md](TESTFLIGHT.md) for App Store Connect setup and the required
GitHub secrets.

## Known caveats

- Top Shelf extensions and sound are deferred (v1.1) — see `nine/DEVIATIONS.md`.
- The localization lane was knowingly stale — its symbol anchors no longer
  matched the redesigned sheets, so it could not even reach prefs or home. It was
  repointed in the daily/streak removal PR (2026-08-02): prefs arrives on the
  verbatim wordmark (the sheet exposes no symbols and the grabber is localized),
  home arrives on the shelf's Next channel chevron, and the status-bar clock is
  masked so a modal sheet cannot rot the prefs baselines every minute.
- `ja-home` AX baselines still rot when the rendered date changes *width* (a
  single-to-double-digit day, or a longer month name). Daily rot is masked;
  monthly rot is not. Fixing it means pinning the clock in the seeded state,
  which is simrig's territory and a change all three lanes would inherit.
