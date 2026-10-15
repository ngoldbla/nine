# PRD-37 — The Spread (iPhone Duo)

**Status:** Proposed · **Thread:** `nine/` + `couchkit/` · **Release:** 1.2
**One-liner:** Folded, the iPhone Duo is an iPhone and Nine draws exactly what it
draws today. Open, it is a book spread: a 550.5pt board whose crease falls on the
board's own thick box rule, the controls on one page and the digits on the
other, and every other surface laid out so nothing but that rule ever sits
under the fold.

> The geometry in §1 is measured, not recalled. Every number cites where it was
> read: the iOS 27.1 SDK, Xcode 27.1 RC's `iPhone Duo` device type, or a probe
> app running on that device type in the iOS 27.1 simulator (build 24A94232).
> Apple's Human Interface Guidelines say nothing about the Duo yet; where this
> PRD needed a design rule and Apple had none, it says so and names the source
> it used instead.

## 1. The device, measured

### 1.1 Sources, in order of trust

| Source | What it gave |
|---|---|
| iOS 27.1 SDK + Apple's API reference (developer.apple.com, read 2026-10-13) | `DeviceHinge` / `onHingeChange(isEnabled:_:)` (SwiftUI), `UIHinge` / `UIHingeInteraction` (UIKit), `ReservedRegion` with kinds `.occlusion` and `.division`, `ArrangementView`. All iOS **27.1**, marked beta. A probe compiled against the SDK confirms every signature. |
| Xcode 27.1 RC (27A9275), `iPhone Duo.simdevicetype` | Model `iPhone19,4`, `minRuntimeVersion` 27.1, two integrated panels in `capabilities.plist` → `displays` |
| Probe app on that device, iOS 27.1 simulator | Everything in §1.3–1.6: window, safe area, size classes, hinge, regions, Apple's own split |
| Apple HIG (`layout`, `designing-for-ios`, `multitasking`, `going-full-screen`, What's New) | **Nothing.** No Duo, hinge or fold guidance exists yet. |
| Android `FoldingFeature.isSeparating` (developer.android.com) | Precedent only: "folds on flexible screens should be treated as separating when they are not `FLAT`" — the same line Apple draws with `isActive`. |

Xcode 26.6 has no Duo device type and its iOS 26.5 SDK no hinge API
(`grep -i hinge|fold|posture` over the UIKit headers finds only
`isPrefetchingEnabled`). The Duo needs Xcode 27.1 RC or 27.2 beta and the iOS
27.1 simulator runtime; the 27.2 beta 2 notes call it "iOS SDK and simulator
support for iPhone Duo".

### 1.2 The two panels (device type)

| Panel | Pixels | Scale | Points | Corners (UL/UR/LR/LL) | Native orientation |
|---|---|---|---|---|---|
| `LCD` (`primary`, the main screen, Dynamic Island) | 1398×2034 | 3 | **466×678** | 8 / 59 / 59 / 8 | 0 |
| `LCD-1` (`primary-1`) | 2007×2853 | 3 | **669×951** | 55 all | 270 (landscape-native) |

`LCD` is the outer screen, used folded. `LCD-1` is the inner screen, used open;
the outer screen stays connected (`UIScreen` count 2) but dark.

### 1.3 Postures

| Posture | Hinge (`onHingeChange`) | Window | Size classes (h × v) | Safe area (t / l / b / r) | `.division` region |
|---|---|---|---|---|---|
| **Folded** | `.closed`, 0° | 466×678, portrait | compact × regular | 0 / 0 / 34 / **84** | none |
| **Open, bent** | `.partiallyOpen` (127.8° measured; 118–172° seen in transit) | 951×669, landscape | regular × regular | 0 / 0 / 34 / **84** | x 455.5–495.5, **active** |
| **Open, flat** | `.fullyOpen`, 180° | 951×669, landscape | regular × regular | 0 / 0 / 34 / **84** | x 455.5–495.5, **inactive** |

- **The 84pt right inset is the iOS 27 vertical status bar** — a pill on the
  trailing edge (`verticalBarEdge` / `toolbarVerticalEdge` in the iOS 27 API
  notes), measured as an `.occlusion` region of 84×120 open and 84×170 folded.
  The top edge is free; the trailing edge is not. Today's layouts already respect
  it because it arrives as a safe-area inset.
- **Bent and flat are the same window.** Nothing about size, traits or safe area
  changes between ~172° and ~118°. The only signals are the hinge status and the
  division region's `isActive`.
- **The division region** is 40pt wide, full height, with `margins` of 20pt on
  each side (documented as kept clear "for interactive content"). The crease
  itself is **x 475.5**. Because the status bar takes 84pt on the right, the
  crease is 42pt right of the safe area's centre (433.5).
- **Orientation:** Nine is portrait-only on iPhone (`project.yml`
  `UISupportedInterfaceOrientations`), and open it is still given the landscape
  951×669 window — the same window a probe declaring every orientation gets. The
  fold is therefore always vertical. Rotating the open device is **not
  measured** (Device Hub's rotate control was not exercised).

### 1.4 How a running app is told

- **Fold or unfold:** the window resizes (466×678 ↔ 951×669) and the size
  classes change (compact ↔ regular width). A `GeometryReader` sees the new size;
  `BoardCompositionRules.resolve` already re-runs from `geo.size`, and game state
  lives in `AppModel`, so no relaunch is needed. Measured so far: today's build
  re-lays out its first-run screen from folded to open without relaunching.
  Fold and unfold **mid-game** is verified as part of §6.
- **Bend or flatten:** no resize. `onHingeChange` / `UIHingeInteraction` fire,
  and the division region flips `isActive`. A *plain*
  `reservedRegions(kind: .division)` returns the region **only while active**;
  `options: .includeInactive` returns it in both states. (Apple's text says the
  plain query returns regions "regardless of whether they are currently
  active"; measured, it does not.)
- **Transitions are not clean.** During a fold the UIKit dump paired the new
  window with the old window's regions, rotated (`division (0, 455.5, 669×40)`
  inside a 466pt window). The `.occlusion` regions were also absent at first
  launch and appeared only after the first posture change. A region is trusted
  only when its frame lies inside the current bounds.

### 1.5 Apple's own two-pane layout, measured

`ArrangementView` with `.split`, on the same device:

| Posture | Primary | Secondary |
|---|---|---|
| Folded | 0,0 382×322 | 0,322 382×322 (stacked) |
| Flat | 0–433.5 | 433.5–867 — the safe area halved; **the secondary pane runs over the crease** |
| Bent | 0–455.5 | 495.5–867 — **the band is cleared exactly** |

### 1.6 The simulator

- Device type `iPhone Duo` (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`),
  runtime iOS 27.1 (24A94232, 7.85 GB). Both arrive with Xcode 27.1 RC.
- **There is no scriptable posture control.** `simctl` has none; XCTest has none.
  Device Hub has three toolbar buttons — Closed, Partially Open, Open — and its
  window exposes no accessibility tree, so posture is set by a person.
- Known issues (Xcode 27.1/27.2 notes): StandBy and most app extensions do not
  run in the Duo runtime; screenshots may be black for minutes after boot;
  "VoiceOver, the Accessibility Inspector, and other accessibility tools cannot
  convey screen content on an iPhone Duo within Device Hub" (187148389).

## 2. The problem

Today's build on an open Duo, measured: the game screen's column composition
centres a **425pt board** in the 867×635 safe area, so the crease falls **39%
across column 6**, through digits. The home shelf's two-column pair puts its
gutter at x 423.5–443.5, left of the crease, so the **whole right column
straddles it**. `GlassSheet`'s trailing panel lands its leading edge at x 471,
**4.5pt over the crease**. The welcome card, School index and tutorial all
centre on 433.5 and cross it.

## 3. Decisions

Made with the owner on 2026-10-14, against an interactive mockup drawn at the
measured sizes:

| Question | Decision | Rejected, and why |
|---|---|---|
| Folded | **Today's iPhone layout, unchanged** | — |
| Open, flat | **Big board on the box rule** (§4.2) | ArrangementView split: 385.5pt board, smallest open option; fixed panes at the fold: 407.5pt |
| Open, bent | **The same big board** — nothing reflows when the hinge flexes | Apple's split resizes the board by 22pt whenever the hinge crosses ~156° |
| Scope | **Every surface** (§4.4) | game only; game + shelf |
| Coach card | **Draggable, open Duo only**, rests wherever dropped, not remembered (§4.5) | fixed placement; draggable everywhere |
| Toolchain | **CI and release lanes move to Xcode 27.1 in this PR, failing loudly when absent** (§5) | keep CI on 26 and flip later; self-hosted runner |

## 4. Design

### 4.1 One measurement, one pure function

The decision lives in `Sources/Shared/DraftingTable.swift` beside
`BoardCompositionRules`, Linux-clean like the rest of that file:

```swift
/// A fold that splits the window, in the window's own points (safe-area space).
public struct FoldBand: Equatable, Sendable {
    public let leading: Double    // x of the band's leading edge (455.5 on the Duo)
    public let trailing: Double   // x of its trailing edge (495.5)
    public var crease: Double { (leading + trailing) / 2 }
    public let isActive: Bool     // bent (true) or flat (false); layout does not depend on it
}

public enum FoldRules {
    /// Accepts a band only if it is vertical, full-height, inside the bounds and
    /// leaves two usable panes; otherwise nil, and every caller takes today's path.
    public static func validate(_ band: FoldBand?, width: Double, height: Double,
                                regionHeight: Double) -> FoldBand?
    /// The game screen's spread, or nil when no box-rule board beats the column.
    public static func spread(width: Double, height: Double, band: FoldBand) -> Spread?
    public static func shelfPanes(width: Double, band: FoldBand) -> ShelfPair?
    public static func panelFrame(width: Double, band: FoldBand) -> (x: Double, width: Double)?
}
```

`BoardComposition` gains a third case, `.spread(Spread)`, and
`BoardCompositionRules.resolve(width:height:fold:)` gains an optional `fold`
parameter that defaults to `nil`. **With `fold == nil` the function is the
existing function** — the new parameter is consulted before anything else and
only when present — and a test sweeps the existing thirty-window table to pin
that the result is identical with and without the parameter.

**Gating is on measured geometry only.** No model string, no idiom, no hinge
angle. A future foldable with a different band position gets the same solver;
one with a horizontal fold, a band too wide, or panes too narrow gets `nil` from
`validate` and therefore today's layout — it degrades to an iPhone or iPad
layout, never to a broken one. `isActive` is carried for the record and for the
rose (§4.4) but does not change the composition, which is the "nothing moves
when the hinge flexes" decision expressed as a type.

### 4.2 The box-rule board

The board is placed so the crease lands on a thick box rule: for
`k ∈ {1, 2}` (rule after column 3 or column 6), `left = crease − (k/3)·side`.
For each `k` the solver takes the largest `side` satisfying:

| Constraint | Duo value |
|---|---|
| Control column fits on the leading side: `left − boardInset − gutter − controlColumnWidth − outerPadding ≥ 0` | `left ≥ 104` |
| Digit pad fits on the trailing side with **44pt-wide keys** (`Hit.min`): `left + side + boardInset + gutter + padMinWidth + outerPadding ≤ width`, `padMinWidth = 3·44 + 2·padKeyGap + 2·padTrayPadding = 164` | `left + side ≤ 659` |
| Height: `side ≤ height − 2·outerPadding − 2·boardInset` | `side ≤ 587` |
| Never costs board: `side ≥ columnBoardSide(width, height)` | `side ≥ 425` |

and keeps the larger of the two. On the Duo `k = 2` binds on the pad:

| | Value |
|---|---|
| Board side | **550.5pt** (cell 61.2pt — 52% larger than the iPhone 17 Pro's 40.2pt) |
| Board x | 108.5 – 659, crease on the rule after column 6 |
| Board y | centred: 42.25 – 592.75 |
| Control column | x 16 – 76 (the shipped 60pt), 24.5pt clear of the board's glass plane |
| Digit pad | x 687 – 851, 3×3, keys 44.0pt wide (the binding constraint) |

The mockup first showed 557pt; at 557 the keys are 43.3pt wide, under the
minimum tap target, which is why the constraint is in the solver and not in a
constant.

### 4.3 Reading the band

One App-layer reader, compiled only where the API exists:

```swift
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)
```

`8.0.85.29` is the SwiftUI module version in the iOS 27.1 SDK (26.6 ships
`8.0.84.1.104`). A compiler check cannot be used: Xcode 27.0 and 27.1 both ship
Swift 6.4, and only 27.1 has the API. Inside, `if #available(iOS 27.1, *)`,
because Nine still deploys to iOS 18.

The reader sits once at the root of the iOS scene, queries
`reservedRegions(kind: .division, options: .includeInactive)` from a
`GeometryReader` in safe-area space, passes the result through
`FoldRules.validate`, and publishes it as `\.foldBand` in the environment. Every
surface below reads that one value. On every non-Duo device, on every build made
without the 27.1 SDK, and in every transitional frame the validator rejects, it
is `nil`, and the surface takes the code path it takes today.

### 4.4 Every surface, open

| Surface | Open-Duo layout | Source of the numbers |
|---|---|---|
| **Game** | §4.2. The difficulty / clock / mistakes / remaining readout (`railHeader`) sits at the top of the 164pt strip above the digit pad, clear of the board as round 4 requires. Toasts, tips, the completion chip, the auto-notes chip and the composing/parlor chips stay over the board, re-centred on box columns 1–6 (x ≈ 292) | `FoldRules.spread` |
| **Flick rose** | Already clamped inside the board frame (`RoseLens.anchoredCentre`). **When the band is active**, the ring is also kept clear of the crease: on the cursor's side when it fits, otherwise on the other side. At 550.5pt the plate is 245.6pt wide (`plateSpan` × scale 0.606); left of the crease there are 367pt and right of it 183.5pt, so a cursor in columns 7–9 opens its ring over columns 1–6. The ring never covers the cursor cell either way | `RoseLens.creaseSafeX` |
| **Preferences, History, Boards** | `GlassSheet`'s trailing panel fills the right pane: x 511.5 – 851 (339.5 wide, against 380 elsewhere) | `FoldRules.panelFrame`, passed to CouchKit as `\.couchPanelLeadingInset` |
| **Debrief, stats drawer** | The same right-pane panel frame | `FoldRules.panelFrame` |
| **Coach and Why cards** | Open in the pane **not** containing the cell they discuss; draggable (§4.5) | `FoldRules` + cursor column |
| **Home shelf, Channel page** | The existing two-column pair with the fold band as the gutter: 24 – 455.5 (431.5) and 495.5 – 843 (347.5). Card order unchanged | `FoldRules.shelfPanes` |
| **First run (welcome card)** | Centred in the left pane, clamped to 423.5 | left pane |
| **Tutorial** | A book spread: 407.5pt board in the left pane, narration card in the right pane. **Smaller than the game board** — the 164pt strip beside the game board cannot hold narration | left/right panes |
| **Technique School** | Index in the left pane, 407.5 wide; the right pane is empty ground — no new master–detail | left pane |
| **Share sheet** | Untouched; iOS presents it | — |

Bent, nothing interactive sits inside the band's 20pt margins **except the
board's own cells in columns 6 and 7**, whose inner 20pt fall inside them. That
is the accepted cost of not reflowing on a bend.

CouchKit change: `GlassSheet` reads an optional environment value
(`couchPanelLeadingInset`, default `nil`) and, when set, uses it as the trailing
panel's leading edge instead of `maxWidth: 380`. `couchkit/API.md` records the
new key. With the default, the panel is byte-for-byte today's.

### 4.5 The coach card is draggable — 1.2's one new input concept

`EXECUTING-A-PRD.md` §1 allows one new input concept per release. This is it,
and it is confined to the open Duo:

- The card opens in the pane opposite the hinted cell.
- A drag moves it freely; it **rests wherever it is dropped**, including over the
  crease or over the hinted cell — the owner's explicit choice over snapping.
- The position is **not remembered**; each new hint starts in the opposite pane.
  No persisted state, so none of `EXECUTING-A-PRD.md` §2's persistence rules
  are touched.
- VoiceOver is unaffected: dragging is a visual convenience, and the card's
  accessibility element and its reading order do not change.
- Folded, and on every other device, the card is today's fixed card.

## 5. Toolchain and CI

The Duo layout only exists in binaries built with the iOS 27.1 SDK. This PR
therefore moves the toolchain, which also moves every platform's release build:

- `nine-engine.yml`, `nine-accessibility.yml` and `testflight-tvos.yml` change
  `runs-on: macos-latest` to `runs-on: xcode-27` (GitHub's preview image) and
  select `/Applications/Xcode_27.1*.app`. **If it is absent the job fails with a
  message naming the missing Xcode** — there is no fallback to Xcode 26.
- The accessibility lane's baselines record their runtime (`runtime: 26.5` in every header). On the Xcode 27 image they run on iOS 27.1, so they are **re-recorded on iOS 27.1 from `main`'s unmodified code** in their own commit, and the branch is then verified against them byte for byte — the runtime move and the feature are never in the same diff.
- As of 2026-10-14 GitHub has not deployed Xcode 27.1 RC to that image
  (actions/runner-images#14850, `awaiting-deployment`; the image ships 27.0).
  Until it does, the PR's checks fail by design and the PR cannot merge green.
- Merging to `main` runs `beta_all`, so the first merge after this one uploads
  TestFlight builds for every platform made with Xcode 27.1 on a preview image.
- `MARKETING_VERSION` is not changed here. Nothing in this PR touches App Store
  Connect, signing, match, or the 1.1 builds in review.

## 6. Verification

1. **Pure tests** (`swift test`, the PR gate): the Duo spread is 550.5 at x
   108.5; keys never under 44pt; the control column always fits; thirty windows
   give identical compositions with `fold: nil`; a stale band (outside the
   bounds, rotated, wrong height), a horizontal band, a too-wide band and
   too-narrow panes all validate to `nil`; shelf panes, panel frame and the
   coach card's opening pane.
2. **Harnesses on the Duo.** `scripts/shotlist.py` gains `duo-folded` and
   `duo-open`, on iOS 27.1. Because posture cannot be scripted, the lane stops
   and asks the operator to set it in Device Hub, then checks it took (the app's
   window width in the AX tree, or the inner display not being black). Posture
   survives relaunch, so it is set once per run. Simulators the harness erases
   are re-slimmed with `simslim on <udid> --keep com.apple.gamed`.
   `ax-snapshot.py`, `contrast-harness.py` and `loc-harness.py` take a device
   argument (they hardcode `iPhone 17 Pro` today) and keep per-device
   baselines. If the AX tools cannot read the Duo (known issue 187148389), that
   lane is recorded in `DEVIATIONS.md` with the failing output rather than
   skipped silently.
3. **Zero change elsewhere.** `simrig.newest_ios_runtime()` would move the
   existing baselines onto iOS 27.1 the moment it is installed, so the harnesses
   gain a runtime pin. `main` and the branch are each built with the **same**
   toolchain (once with Xcode 26.6, once with 27.1) and run on iPhone 17 Pro and
   iPad Pro 11" (M5) on iOS 26.5: the AX snapshots, the contrast matrix and the
   localization baselines must match **byte for byte**. Screenshots cannot —
   Liquid Glass samples a live blur, which is why `shotlist.py` keeps no
   baselines — so those are diffed with a tolerance and every pair is looked at.

## 7. What is not done, and what is not known

- Taps inside the fold band while flat are not measured. iOS reports the band
  inactive then and Apple's split places content over it.
- The open device rotated is not measured; Nine is given landscape regardless of
  its portrait-only declaration, and §4.3's validator rejects a horizontal band.
- Xcode 27.0's SwiftUI module version is not known on this machine; if it equals
  27.1's, the `canImport` guard admits a build that lacks the API and the PR's
  27.0 build (if any) fails to compile rather than silently dropping the layout.
- Posture changes need a person: Device Hub's window exposes no accessibility
  tree, and computer-use clicks into it are refused.
- The tutorial's board is smaller than the game's (407.5 against 550.5).
