# PRD-37 The Spread (iPhone Duo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Folded, the iPhone Duo draws exactly today's iPhone layouts. Open, every surface is laid out around the fold — the game screen as a 550.5pt board whose crease falls on its own box rule — with zero change on every other device.

**Architecture:** One measured input, `FoldBand?`, read once at the iOS scene root from `reservedRegions(kind: .division, options: .includeInactive)` and published through the environment. Every layout decision that consumes it is a pure, Linux-tested function in `Sources/Shared/FoldRules.swift`; every view that consumes it takes today's code path when it is `nil`. CI and the release lanes move to Xcode 27.1, failing loudly where it is absent.

**Tech Stack:** Swift 6.4 / SwiftUI, iOS 27.1 SDK (Xcode 27.1 RC at `/Applications/Xcode-27.1.app`), XCTest via `swift test`, Python 3 harnesses (`nine/scripts/`), XcodeGen, GitHub Actions.

**Spec:** `nine/PRD-37.md` (read it first — §1 holds every measured number this plan uses).

## Global Constraints

- **Zero change elsewhere.** Every new parameter defaults to today's behaviour; with `foldBand == nil` every view takes its current code path. Proven by byte-identical AX / contrast / localization baselines (Task 11).
- **Gate on measured geometry only** — never a model string, idiom, or hinge angle (PRD-37 §4.1).
- **Folded = today's iPhone layout**, unchanged (PRD-37 §3).
- **Open flat and open bent produce the same composition** — `FoldBand.isActive` changes only the rose's crease clamp (PRD-37 §3, §4.4).
- **No new persisted state.** Nothing touches `CouchStored`, KVS, `LibraryEntry` or `NinePrefs` (EXECUTING-A-PRD §2).
- **Golden corpus untouched** — no engine change; `swift test` must stay green including `GoldenCorpusTests`.
- **No new user-facing strings.** `python3 scripts/strings.py --audit` must still report `0 new`.
- **Minimum tap target 44pt** (`Hit.min`): the spread's digit keys are exactly 44.0pt wide.
- **Compile guard for every iOS 27.1 API:** `#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)` plus `if #available(iOS 27.1, *)` inside (deployment target stays iOS 18.0).
- **Do not:** touch App Store Connect, run any fastlane `release`/`store_*`/`beta`/`match` lane, change `MARKETING_VERSION`, edit `Nine.xcodeproj` (edit `project.yml`), rewrite pushed history, or reboot a simulator you did not create. Commit author is `70771914+ngoldbla@users.noreply.github.com` (already in local config).
- **Simulators:** any simulator you erase or create comes up stock; re-slim with `simslim on <udid> --keep com.apple.gamed` (Nine waits on Game Center at launch).
- **Toolchains on this Mac:** `/Applications/Xcode.app` is 26.6 and stays `xcode-select`'s default (other agents use it). Use `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer` for every 27.1 command.

## Review Focus

1. **Open-Duo screenshots of the wrong panel.** `simctl io screenshot` defaults to the outer `primary` panel, which is black when the Duo is open — every Duo-open capture must pass `--display=primary-1`. Pinned in Task 9 (`simrig.screenshot_display`).
2. **A stale fold region mid-transition.** During fold/unfold iOS briefly reports the *old* window's region rotated (`division (0, 455.5, 669×40)` inside a 466pt window). `FoldRules.validate` must reject it, or the folded screen flashes a spread. Pinned in Task 1 (`testATransitionalRotatedRegionIsRejected`).
3. **Folding mid-game.** Fold and unfold with a board half-filled and the rose open must keep every entry, the cursor and the clock, and must not leave the rose stranded off the board. Pinned in Task 11 Step 6 (driven on the device, screenshots before/after).
4. **A coach card dragged off-screen.** It must stay recoverable: tapping the lightbulb again dismisses it, and the next hint opens at its default pane. Pinned in Task 7 (`coachDragOffset` reset on every new advice) and checked in Task 11.
5. **An unknown foldable.** A horizontal fold, a band wider than a quarter of the window, or a pane narrower than 340pt must fall back to today's layout, not to a broken spread. Pinned in Task 1 (`testUnusableBandsFallBackToToday`).

---

## File Map

| File | Responsibility | Task |
|---|---|---|
| `nine/Sources/Shared/FoldRules.swift` (new) | `FoldBand`, `Spread`, `FoldRules` — validation, the box-rule solver, shelf/panel/card/pane geometry | 1, 2 |
| `nine/Sources/Shared/DraftingTable.swift` | `BoardComposition.spread`, `resolve(…fold:)`, `ShelfPair.trailingColumnWidth`, `resolveShelf(…fold:)` | 1, 2 |
| `nine/Sources/Shared/RoseLens.swift` | optional crease clamp | 3 |
| `nine/Tests/SharedTests/FoldRulesTests.swift` (new) | every pure claim | 1, 2, 3 |
| `nine/Sources/App/FoldReader.swift` (new) | `\.foldBand` environment, the guarded probe, `inLeadingFoldPane()` | 4 |
| `nine/Sources/App/NineApp.swift` | `.readsFold()` at the root | 4 |
| `couchkit/Sources/CouchKit/GlassComponents.swift`, `couchkit/API.md` | `\.couchPanelWidth` | 5 |
| `nine/Sources/App/TouchUI.swift` | spread game view, drawer/debrief panel frame, coach/why panes + coach drag, fold shelf | 6, 7, 8 |
| `nine/Sources/App/FirstRun.swift`, `TutorialView.swift`, `SchoolView.swift` | left-pane / book-spread pages | 8 |
| `nine/scripts/simrig.py`, `shotlist.py`, `ax-snapshot.py`, `contrast-harness.py`, `loc-harness.py` | runtime pin, re-slim, Duo devices, posture gate, per-device baselines | 9 |
| `.github/workflows/nine-engine.yml`, `nine-accessibility.yml`, `testflight-tvos.yml` | Xcode 27.1, fail loudly | 10 |
| `nine/Tests/{AX,Contrast,Loc}Baselines/` | re-recorded on iOS 27.1 from `main`'s code; new Duo baselines | 10, 11 |
| `nine/PRD-37.md`, `nine/DEVIATIONS.md` | amendments, record | 0, 11 |

---

### Task 0: Amend PRD-37 with plan-time findings

**Files:**
- Modify: `nine/PRD-37.md` (§4.4 table rows *Game* and *Flick rose*; §5)

Three facts surfaced while planning; the spec must say them before code does.

- [ ] **Step 1: Rose row.** Replace the *Flick rose* row's text with:

```markdown
| **Flick rose** | Already clamped inside the board frame (`RoseLens.anchoredCentre`). **When the band is active**, the ring is also kept clear of the crease: on the cursor's side when it fits, otherwise on the other side. At 550.5pt the plate is 245.6pt wide (`plateSpan` × scale 0.606); left of the crease there are 367pt and right of it 183.5pt, so a cursor in columns 7–9 opens its ring over columns 1–6. The ring never covers the cursor cell either way | `RoseLens.creaseSafeX` |
```

- [ ] **Step 2: Game row.** Replace "Header chips centred on box columns 1–6 (x ≈ 292); toasts and the auto-notes chip likewise" with:

```markdown
The difficulty / clock / mistakes / remaining readout (`railHeader`) sits at the top of the 164pt strip above the digit pad, clear of the board as round 4 requires. Toasts, tips, the completion chip, the auto-notes chip and the composing/parlor chips stay over the board, re-centred on box columns 1–6 (x ≈ 292)
```

- [ ] **Step 3: §5, add a bullet after the `runs-on` bullet:**

```markdown
- The accessibility lane's baselines record their runtime (`runtime: 26.5` in every header). On the Xcode 27 image they run on iOS 27.1, so they are **re-recorded on iOS 27.1 from `main`'s unmodified code** in their own commit, and the branch is then verified against them byte for byte — the runtime move and the feature are never in the same diff.
```

- [ ] **Step 4: Commit**

```bash
cd /Users/aquilops/nine && git add nine/PRD-37.md && git commit -m "PRD-37: rose crease rule, header strip, baseline runtime move

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: The fold band, the validator and the box-rule spread

**Files:**
- Create: `nine/Sources/Shared/FoldRules.swift`
- Modify: `nine/Sources/Shared/DraftingTable.swift` (`BoardComposition`, `resolve`)
- Create: `nine/Tests/SharedTests/FoldRulesTests.swift`

**Interfaces:**
- Consumes: `BoardCompositionRules.{outerPadding 16, controlColumnWidth 60, gutter 20, boardInset 8, padKeyGap 4, padTrayPadding 12, maximumBoardSide 1000, shelfMinimumColumn 340, columnBoardSide(width:height:)}`
- Produces:
  - `public struct FoldBand: Equatable, Sendable { leading: Double; trailing: Double; isActive: Bool; crease: Double; width: Double; init(leading:trailing:isActive:) }`
  - `public struct Spread: Equatable, Sendable { boardSide, boardLeft: Double; ruleAfterColumn: Int; controlColumnX, padX, padWidth, crease: Double; chipCentreOffset: Double }`
  - `public enum FoldRules { static let minimumKeyWidth = 44.0; static var padMinimumWidth: Double; static func validate(_:width:height:regionTop:regionBottom:) -> FoldBand?; static func spread(width:height:band:) -> Spread? }`
  - `BoardComposition.spread(Spread)`, `BoardComposition.spread: Spread?`
  - `BoardCompositionRules.resolve(width:height:fold: FoldBand? = nil)`

- [ ] **Step 1: Write the failing tests**

Create `nine/Tests/SharedTests/FoldRulesTests.swift`:

```swift
// The iPhone Duo's spread, pinned against the measured device (PRD-37).
//
// Every number here is read from the iOS 27.1 simulator, not chosen: the open
// Duo's safe area is 867×635 (951×669 window, 84pt vertical status bar on the
// right, 34pt home indicator), and its fold region is x 455.5–495.5, full
// height. If one of these tests fails, re-measure before you re-tune.
import XCTest
@testable import NineShared

final class FoldRulesTests: XCTestCase {

    static let openWidth = 867.0, openHeight = 635.0
    static let duoBand = FoldBand(leading: 455.5, trailing: 495.5, isActive: false)

    // MARK: Validation

    func testTheMeasuredDuoBandIsAccepted() {
        let band = FoldRules.validate(Self.duoBand, width: Self.openWidth, height: Self.openHeight,
                                      regionTop: 0, regionBottom: 669)
        XCTAssertEqual(band, Self.duoBand)
        XCTAssertEqual(band?.crease, 475.5)
        XCTAssertEqual(band?.width, 40)
    }

    /// Measured mid-fold: the folded 466pt window paired with the open
    /// window's region, rotated. Accepting it would flash a spread on the
    /// folded screen.
    func testATransitionalRotatedRegionIsRejected() {
        let rotated = FoldBand(leading: 0, trailing: 669, isActive: false)
        XCTAssertNil(FoldRules.validate(rotated, width: 382, height: 644,
                                        regionTop: 455.5, regionBottom: 495.5))
    }

    func testUnusableBandsFallBackToToday() {
        let w = Self.openWidth, h = Self.openHeight
        // Horizontal: does not span the height.
        XCTAssertNil(FoldRules.validate(Self.duoBand, width: w, height: h, regionTop: 300, regionBottom: 340))
        // Too wide: more than a quarter of the window.
        XCTAssertNil(FoldRules.validate(FoldBand(leading: 300, trailing: 540, isActive: true),
                                        width: w, height: h, regionTop: 0, regionBottom: h))
        // A pane under the shelf's minimum column.
        XCTAssertNil(FoldRules.validate(FoldBand(leading: 300, trailing: 340, isActive: true),
                                        width: w, height: h, regionTop: 0, regionBottom: h))
        // Outside the bounds.
        XCTAssertNil(FoldRules.validate(FoldBand(leading: 900, trailing: 940, isActive: true),
                                        width: w, height: h, regionTop: 0, regionBottom: h))
        XCTAssertNil(FoldRules.validate(nil, width: w, height: h, regionTop: 0, regionBottom: h))
    }

    // MARK: The spread

    func testTheDuoSpreadPutsTheCreaseOnTheRuleAfterColumnSix() throws {
        let spread = try XCTUnwrap(FoldRules.spread(width: Self.openWidth, height: Self.openHeight,
                                                    band: Self.duoBand))
        XCTAssertEqual(spread.boardSide, 550.5, accuracy: 0.001)
        XCTAssertEqual(spread.boardLeft, 108.5, accuracy: 0.001)
        XCTAssertEqual(spread.ruleAfterColumn, 6)
        XCTAssertEqual(spread.boardLeft + spread.boardSide * 6 / 9, 475.5, accuracy: 0.001)
        XCTAssertEqual(spread.controlColumnX, 16)
        XCTAssertEqual(spread.padX, 687, accuracy: 0.001)
        XCTAssertEqual(spread.padWidth, 164, accuracy: 0.001)
        XCTAssertEqual(spread.chipCentreOffset, -91.75, accuracy: 0.001)
    }

    /// The pad is the binding constraint, and it is the one a player feels:
    /// three keys across must each be at least the 44pt tap target.
    func testEverySpreadKeepsKeysAtLeastFortyFourPointsWide() {
        for crease in stride(from: 380.0, through: 700.0, by: 7.5) {
            for width in stride(from: 760.0, through: 1400.0, by: 40.0) {
                let band = FoldBand(leading: crease - 20, trailing: crease + 20, isActive: true)
                guard let s = FoldRules.spread(width: width, height: 635, band: band) else { continue }
                let key = (s.padWidth - 2 * BoardCompositionRules.padTrayPadding
                           - 2 * BoardCompositionRules.padKeyGap) / 3
                XCTAssertGreaterThanOrEqual(key, 44 - 0.001, "crease \(crease) width \(width)")
                XCTAssertGreaterThanOrEqual(s.boardLeft - BoardCompositionRules.boardInset,
                                            s.controlColumnX + BoardCompositionRules.controlColumnWidth
                                            + BoardCompositionRules.gutter - 0.001)
                let ruleX = s.boardLeft + s.boardSide * Double(s.ruleAfterColumn) / 9
                XCTAssertEqual(ruleX, crease, accuracy: 0.001)
            }
        }
    }

    /// The table's rule, restated for the spread: never adopt a board smaller
    /// than the column would have drawn.
    func testTheSpreadNeverCostsBoard() {
        for crease in stride(from: 380.0, through: 700.0, by: 10.0) {
            let band = FoldBand(leading: crease - 20, trailing: crease + 20, isActive: false)
            guard let s = FoldRules.spread(width: 867, height: 635, band: band) else { continue }
            XCTAssertGreaterThanOrEqual(s.boardSide,
                                        BoardCompositionRules.columnBoardSide(width: 867, height: 635))
        }
    }

    // MARK: resolve(…fold:)

    func testResolveAdoptsTheSpreadOnlyWithABand() {
        let open = BoardCompositionRules.resolve(width: Self.openWidth, height: Self.openHeight,
                                                 fold: Self.duoBand)
        XCTAssertEqual(open.spread?.boardSide ?? 0, 550.5, accuracy: 0.001)
        XCTAssertEqual(open.boardSide, 550.5, accuracy: 0.001)
        XCTAssertNil(BoardCompositionRules.resolve(width: Self.openWidth,
                                                   height: Self.openHeight).spread)
    }

    /// Flat and bent are the same composition — the owner's "nothing moves when
    /// the hinge flexes", as a test.
    func testFlatAndBentResolveIdentically() {
        let bent = FoldBand(leading: 455.5, trailing: 495.5, isActive: true)
        XCTAssertEqual(BoardCompositionRules.resolve(width: 867, height: 635, fold: Self.duoBand),
                       BoardCompositionRules.resolve(width: 867, height: 635, fold: bent))
    }

    /// Zero change elsewhere: with no fold, every window the drafting-table
    /// tests sweep resolves exactly as it did before the parameter existed.
    func testNoFoldIsTodaysFunctionEverywhere() {
        for width in stride(from: 320.0, through: 2000.0, by: 20.0) {
            for height in stride(from: 320.0, through: 1440.0, by: 20.0) {
                XCTAssertEqual(BoardCompositionRules.resolve(width: width, height: height, fold: nil),
                               BoardCompositionRules.resolve(width: width, height: height))
                XCTAssertNil(BoardCompositionRules.resolve(width: width, height: height).spread)
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/aquilops/nine/nine && swift test --filter FoldRulesTests 2>&1 | tail -5`
Expected: compile failure — `cannot find 'FoldBand' in scope`.

- [ ] **Step 3: Implement**

Create `nine/Sources/Shared/FoldRules.swift`:

```swift
// FoldRules.swift — the iPhone Duo's open screen, as pure functions (PRD-37).
//
// The input is the fold region iOS reports, never the device: a band of
// window that `reservedRegions(kind: .division)` says splits the content. On
// the Duo it is x 455.5–495.5 of an 867×635 safe area, crease at 475.5. A
// future foldable with a different band gets the same solver; one with a band
// this file cannot use gets `nil`, and every caller takes today's path.
//
// Linux-clean on purpose, like `DraftingTable.swift` and `RoseLens.swift`: no
// SwiftUI, no CoreGraphics. `FoldRulesTests` sweeps it without a simulator.
import Foundation

/// A fold that splits the window, in the window's safe-area points.
public struct FoldBand: Equatable, Sendable {
    /// The band's leading edge, margins included (455.5 on the Duo).
    public let leading: Double
    /// Its trailing edge (495.5).
    public let trailing: Double
    /// Bent (true) or flat (false). Carried for the rose's clamp only — the
    /// composition is the same either way, so nothing reflows as the hinge
    /// flexes mid-solve.
    public let isActive: Bool

    public init(leading: Double, trailing: Double, isActive: Bool) {
        self.leading = leading
        self.trailing = trailing
        self.isActive = isActive
    }

    /// The crease itself, at the band's centre (475.5).
    public var crease: Double { (leading + trailing) / 2 }
    public var width: Double { trailing - leading }
}

/// The game screen laid out as an open book. Points, safe-area space.
public struct Spread: Equatable, Sendable {
    public let boardSide: Double
    /// The grid's leading edge (the glass plane starts `boardInset` before it).
    public let boardLeft: Double
    /// The crease lies on the thick rule after this column: 3 or 6.
    public let ruleAfterColumn: Int
    /// Leading edge of the 60pt control column.
    public let controlColumnX: Double
    /// Leading edge and width of the strip that holds the readout and the pad.
    public let padX: Double
    public let padWidth: Double
    public let crease: Double

    /// How far the board's floating chips move so they centre on the columns
    /// before the crease rather than on the whole board (−91.75 on the Duo).
    public var chipCentreOffset: Double {
        (crease - boardLeft) / 2 - boardSide / 2
    }
}

public enum FoldRules {

    /// `Hit.min`, restated because this file may not import the App layer.
    public static let minimumKeyWidth = 44.0
    /// A band wider than this is not a fold Nine knows how to lay out around.
    public static let maximumBandFraction = 0.25
    /// Three 44pt keys, their two gaps and the tray's own padding: 164.
    public static var padMinimumWidth: Double {
        3 * minimumKeyWidth + 2 * BoardCompositionRules.padKeyGap
            + 2 * BoardCompositionRules.padTrayPadding
    }

    /// The band, if it is one this file can lay out around.
    ///
    /// `regionTop`/`regionBottom` are the region's vertical extent in the same
    /// space: a fold must cross the whole safe height. The Duo's region is
    /// 669pt tall against a 635pt safe height, so it passes; the rotated
    /// region iOS reports for a frame mid-fold does not.
    public static func validate(
        _ band: FoldBand?, width: Double, height: Double,
        regionTop: Double, regionBottom: Double
    ) -> FoldBand? {
        guard let band else { return nil }
        guard band.leading > 0, band.trailing < width, band.width > 0,
              band.width <= width * maximumBandFraction,
              regionTop <= 0.5, regionBottom >= height - 0.5,
              band.leading >= BoardCompositionRules.shelfMinimumColumn,
              width - band.trailing >= BoardCompositionRules.shelfMinimumColumn
        else { return nil }
        return band
    }

    /// The largest board whose crease lands on a box rule while the control
    /// column fits before it and 44pt keys fit after it — or nil when no such
    /// board beats the column.
    public static func spread(width: Double, height: Double, band: FoldBand) -> Spread? {
        typealias R = BoardCompositionRules
        let crease = band.crease
        let leadingReserve = R.outerPadding + R.controlColumnWidth + R.gutter + R.boardInset
        let trailingReserve = R.boardInset + R.gutter + padMinimumWidth + R.outerPadding
        let heightCap = height - 2 * R.outerPadding - 2 * R.boardInset
        var best: Spread?
        for columns in [6, 3] {
            let before = Double(columns) / 9
            let side = min((crease - leadingReserve) / before,
                           (width - trailingReserve - crease) / (1 - before),
                           heightCap,
                           R.maximumBoardSide)
            guard side > 0, side > (best?.boardSide ?? 0) else { continue }
            let left = crease - before * side
            let padX = left + side + R.boardInset + R.gutter
            best = Spread(boardSide: side, boardLeft: left, ruleAfterColumn: columns,
                          controlColumnX: R.outerPadding, padX: padX,
                          padWidth: width - R.outerPadding - padX, crease: crease)
        }
        guard let best, best.boardSide >= R.columnBoardSide(width: width, height: height)
        else { return nil }
        return best
    }
}
```

In `nine/Sources/Shared/DraftingTable.swift`, add the case and accessor to `BoardComposition` (after `case table(DraftingTable)`):

```swift
    /// PRD-37's spread: the open iPhone Duo. The board sits with the crease on
    /// its own box rule, the controls on one page and the digits on the other.
    case spread(Spread)
```

and extend `boardSide`'s switch and add an accessor:

```swift
        case .spread(let spread): return spread.boardSide
```

```swift
    public var spread: Spread? {
        if case .spread(let spread) = self { return spread }
        return nil
    }
```

Replace the signature and first line of `resolve`:

```swift
    /// The composition for a window of this size — and, on a foldable, for the
    /// fold iOS reports in it (PRD-37). `fold == nil` is today's function.
    public static func resolve(width: Double, height: Double,
                               fold: FoldBand? = nil) -> BoardComposition {
        if let fold, let spread = FoldRules.spread(width: width, height: height, band: fold) {
            return .spread(spread)
        }
        let column = columnBoardSide(width: width, height: height)
```

(the rest of the body is unchanged).

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/aquilops/nine/nine && swift test --filter "FoldRulesTests|DraftingTableTests" 2>&1 | tail -5`
Expected: all pass. Then the whole suite: `swift test 2>&1 | grep -E "Executed|passed after|failed" | tail -3` — all pass, GoldenCorpus included.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add nine/Sources/Shared/FoldRules.swift nine/Sources/Shared/DraftingTable.swift nine/Tests/SharedTests/FoldRulesTests.swift
git commit -m "PRD-37: FoldBand, its validator and the box-rule spread

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Every other pane — shelf, panel, cards, left pane

**Files:**
- Modify: `nine/Sources/Shared/FoldRules.swift`, `nine/Sources/Shared/DraftingTable.swift` (`ShelfPair`, `resolveShelf`)
- Test: `nine/Tests/SharedTests/FoldRulesTests.swift`

**Interfaces:**
- Consumes: Task 1's `FoldBand`, `Spread`.
- Produces:
  - `ShelfPair.trailingColumnWidth: Double` (init param defaults to `columnWidth`); `totalWidth` uses it.
  - `BoardCompositionRules.resolveShelf(width:height:fold: FoldBand? = nil)`
  - `FoldRules.shelfPair(width:height:band:) -> ShelfPair?`
  - `FoldRules.panelInset = 16.0`, `FoldRules.panelWidth(width:band:) -> Double`
  - `public enum FoldPane: Equatable, Sendable { case leading, trailing }`
  - `FoldRules.cardPane(for cells: [Int], spread: Spread) -> FoldPane`

- [ ] **Step 1: Append the failing tests** to `FoldRulesTests`:

```swift
    // MARK: The shelf

    func testTheDuoShelfUsesTheBandAsItsGutter() throws {
        let pair = try XCTUnwrap(BoardCompositionRules.resolveShelf(
            width: Self.openWidth, height: Self.openHeight, fold: Self.duoBand).pair)
        XCTAssertEqual(pair.columnWidth, 431.5, accuracy: 0.001)
        XCTAssertEqual(pair.trailingColumnWidth, 347.5, accuracy: 0.001)
        XCTAssertEqual(pair.gutter, 40, accuracy: 0.001)
        XCTAssertEqual(pair.outerPadding, 24)
        XCTAssertEqual(pair.totalWidth, Self.openWidth, accuracy: 0.001)
    }

    func testNoFoldShelfIsTodaysShelfEverywhere() {
        for width in stride(from: 320.0, through: 2000.0, by: 20.0) {
            for height in stride(from: 320.0, through: 1440.0, by: 20.0) {
                let today = BoardCompositionRules.resolveShelf(width: width, height: height)
                XCTAssertEqual(BoardCompositionRules.resolveShelf(width: width, height: height, fold: nil), today)
                if let pair = today.pair { XCTAssertEqual(pair.trailingColumnWidth, pair.columnWidth) }
            }
        }
    }

    // MARK: Panels and cards

    /// GlassSheet pads its trailing panel 16pt from the edge; on the Duo its
    /// leading edge must land 16pt past the band, at 511.5.
    func testTheDuoPanelFillsTheRightPane() {
        let w = FoldRules.panelWidth(width: Self.openWidth, band: Self.duoBand)
        XCTAssertEqual(w, 339.5, accuracy: 0.001)
        XCTAssertEqual(Self.openWidth - FoldRules.panelInset - w, 511.5, accuracy: 0.001)
    }

    func testACardOpensOppositeTheCellsItDiscusses() throws {
        let s = try XCTUnwrap(FoldRules.spread(width: Self.openWidth, height: Self.openHeight,
                                               band: Self.duoBand))
        XCTAssertEqual(FoldRules.cardPane(for: [3 * 9 + 1], spread: s), .trailing)      // r4c2
        XCTAssertEqual(FoldRules.cardPane(for: [3 * 9 + 7], spread: s), .leading)       // r4c8
        XCTAssertEqual(FoldRules.cardPane(for: [0, 1, 8], spread: s), .trailing)        // majority left
        XCTAssertEqual(FoldRules.cardPane(for: [], spread: s), .trailing)               // nothing to cover
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/aquilops/nine/nine && swift test --filter FoldRulesTests 2>&1 | tail -5`
Expected: compile failure — `extra argument 'fold'` / `value of type 'ShelfPair' has no member 'trailingColumnWidth'`.

- [ ] **Step 3: Implement**

In `DraftingTable.swift`, replace `ShelfPair`'s body with:

```swift
public struct ShelfPair: Equatable, Sendable {
    /// The leading column's width — and the trailing one's, except on a
    /// foldable, where the fold band is the gutter and the panes differ.
    public let columnWidth: Double
    public let gutter: Double
    public let outerPadding: Double
    public let trailingColumnWidth: Double

    public init(columnWidth: Double, gutter: Double, outerPadding: Double,
                trailingColumnWidth: Double? = nil) {
        self.columnWidth = columnWidth
        self.gutter = gutter
        self.outerPadding = outerPadding
        self.trailingColumnWidth = trailingColumnWidth ?? columnWidth
    }

    public var totalWidth: Double {
        columnWidth + trailingColumnWidth + gutter + 2 * outerPadding
    }
}
```

and `resolveShelf`'s signature and first line:

```swift
    public static func resolveShelf(width: Double, height: Double,
                                    fold: FoldBand? = nil) -> ShelfComposition {
        if let fold, let pair = FoldRules.shelfPair(width: width, height: height, band: fold) {
            return .pair(pair)
        }
        let usable = min(width, shelfMaximumWidth) - 2 * shelfOuterPadding - shelfGutter
```

Append to `FoldRules.swift`:

```swift
/// Which side of the fold.
public enum FoldPane: Equatable, Sendable { case leading, trailing }

extension FoldRules {

    /// The shelf's two columns, one per pane, the band as the gutter.
    public static func shelfPair(width: Double, height: Double, band: FoldBand) -> ShelfPair? {
        typealias R = BoardCompositionRules
        let leading = band.leading - R.shelfOuterPadding
        let trailing = width - R.shelfOuterPadding - band.trailing
        guard height >= R.shelfMinimumHeight,
              leading >= R.shelfMinimumColumn, trailing >= R.shelfMinimumColumn
        else { return nil }
        return ShelfPair(columnWidth: leading, gutter: band.width,
                         outerPadding: R.shelfOuterPadding, trailingColumnWidth: trailing)
    }

    /// GlassSheet's own trailing padding, which the panel is measured inside.
    public static let panelInset = 16.0

    /// The width a trailing panel takes so it fills the right pane exactly.
    public static func panelWidth(width: Double, band: FoldBand) -> Double {
        width - band.trailing - 2 * panelInset
    }

    /// The pane a card about `cells` opens in: whichever holds fewer of them,
    /// so the card does not cover what it is talking about. Ties and empty
    /// lists go to the trailing pane, where the spread's pad already is.
    public static func cardPane(for cells: [Int], spread: Spread) -> FoldPane {
        let leading = cells.filter { $0 % 9 < spread.ruleAfterColumn }.count
        return leading >= cells.count - leading ? .trailing : .leading
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter "FoldRulesTests|DraftingTableTests"`, then the full `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add nine/Sources/Shared nine/Tests/SharedTests/FoldRulesTests.swift
git commit -m "PRD-37: shelf, panel and card panes around the fold

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The rose keeps clear of an active crease

**Files:**
- Modify: `nine/Sources/Shared/RoseLens.swift` (init signature; the final `(self.centreX, self.centreY) = …` line; new static func)
- Test: `nine/Tests/SharedTests/FoldRulesTests.swift`

**Interfaces:**
- Produces: `RoseLens.init(cursor:side:inset:pencil:scale:clamped:crease: Double? = nil)` — `crease` is **board-local** x; `public static func creaseSafeX(_ x: Double, half: Double, crease: Double, cursorX: Double, lo: Double, hi: Double) -> Double` (view-space).

- [ ] **Step 1: Append the failing tests:**

```swift
    // MARK: The rose

    /// 550.5pt board, crease 367pt in: the plate (245.6pt) fits left of the
    /// crease and not right of it.
    func testTheRoseStaysClearOfAnActiveCrease() {
        let side = 550.5, inset = 8.0, crease = 367.0
        let scale = RoseLens.scale(forSide: side)
        let half = RoseLens.plateSpan(pencil: false, scale: scale) / 2
        for cursor in 0..<81 {
            let lens = RoseLens(cursor: cursor, side: side, inset: inset, pencil: false,
                                scale: scale, crease: crease)
            let straddles = lens.centre.x - half < crease && lens.centre.x + half > crease
            XCTAssertFalse(straddles, "cursor \(cursor) at x \(lens.centre.x)")
        }
    }

    func testNoCreaseIsTodaysRose() {
        for side in [334.0, 386.0, 425.0, 550.5] {
            let scale = RoseLens.scale(forSide: side)
            for cursor in 0..<81 {
                XCTAssertEqual(
                    RoseLens(cursor: cursor, side: side, inset: 8, pencil: false, scale: scale),
                    RoseLens(cursor: cursor, side: side, inset: 8, pencil: false, scale: scale, crease: nil))
            }
        }
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter FoldRulesTests` → `extra argument 'crease'`.

- [ ] **Step 3: Implement.** Add `crease: Double? = nil` as the init's last parameter. Replace the init's final line `(self.centreX, self.centreY) = (view.x - inset, view.y - inset)` with:

```swift
        // PRD-37: on a bent Duo the plate must not lie across the crease.
        // Horizontal only — the vertical placement above is what keeps the
        // cursor cell uncovered, and moving sideways cannot undo it.
        var x = view.x
        if let crease {
            x = Self.creaseSafeX(x, half: half, crease: crease + inset, cursorX: cx,
                                 lo: half + Self.plateMargin,
                                 hi: frameSide - half - Self.plateMargin)
        }
        (self.centreX, self.centreY) = (x - inset, view.y - inset)
```

and add, beside `scale(forSide:)`:

```swift
    /// The plate's centre x moved clear of a crease at `crease` (all view
    /// space): onto the cursor's side when the plate fits there, else onto the
    /// other side, else left where it was (a board too small to matter).
    public static func creaseSafeX(_ x: Double, half: Double, crease: Double,
                                   cursorX: Double, lo: Double, hi: Double) -> Double {
        guard x - half < crease, x + half > crease else { return x }
        let leadingMax = crease - half - plateMargin
        let trailingMin = crease + half + plateMargin
        let leadingFits = leadingMax >= lo, trailingFits = trailingMin <= hi
        if cursorX < crease {
            if leadingFits { return min(x, leadingMax) }
            if trailingFits { return max(x, trailingMin) }
        } else {
            if trailingFits { return max(x, trailingMin) }
            if leadingFits { return min(x, leadingMax) }
        }
        return x
    }
```

- [ ] **Step 4: Run** — `swift test --filter "FoldRulesTests|RoseLensTests"`, then full `swift test`. Expected: all pass (`RoseLensTests` unchanged proves no-crease is today's).

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add nine/Sources/Shared/RoseLens.swift nine/Tests/SharedTests/FoldRulesTests.swift
git commit -m "PRD-37: the rose keeps clear of an active crease

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Read the fold once, at the root

**Files:**
- Create: `nine/Sources/App/FoldReader.swift`
- Modify: `nine/Sources/App/NineApp.swift` (`RootView.body`, last modifier before `#if os(macOS)`)

**Interfaces:**
- Consumes: `FoldRules.validate`, `FoldRules.panelWidth`.
- Produces: `EnvironmentValues.foldBand: FoldBand?`; `View.readsFold()`; `View.inLeadingFoldPane()`. (`FoldState.width` is stored here for Task 5, which publishes `\.couchPanelWidth` from it.)

- [ ] **Step 1: Create `nine/Sources/App/FoldReader.swift`:**

```swift
// FoldReader.swift — the one place the iPhone Duo's fold is measured (PRD-37).
//
// `reservedRegions(kind: .division, options: .includeInactive)` is read from a
// GeometryReader behind the root, validated by `FoldRules.validate`, and
// published as `\.foldBand`. Everything else reads that value; when it is nil
// — every other device, every build without the iOS 27.1 SDK, every frame the
// validator rejects mid-fold — every view takes the path it took before.
//
// `.includeInactive` is not optional: a plain query returns the region only
// while the hinge is bent (measured, contrary to the API text), and the spread
// is the same composition flat or bent.
import SwiftUI
import CouchKit
import NineShared

private struct FoldBandKey: EnvironmentKey {
    static let defaultValue: FoldBand? = nil
}

extension EnvironmentValues {
    var foldBand: FoldBand? {
        get { self[FoldBandKey.self] }
        set { self[FoldBandKey.self] = newValue }
    }
}

private struct FoldState: Equatable {
    var band: FoldBand?
    var width: Double = 0
}

private struct FoldReader: ViewModifier {
    @State private var state = FoldState()

    func body(content: Content) -> some View {
        content
            .environment(\.foldBand, state.band)
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)
            .background { FoldProbe(state: $state) }
            #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)
private struct FoldProbe: View {
    @Binding var state: FoldState

    var body: some View {
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                let measured = Self.measure(proxy)
                Color.clear
                    .onAppear { state = measured }
                    .onChange(of: measured) { _, new in state = new }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    @available(iOS 27.1, *)
    private static func measure(_ proxy: GeometryProxy) -> FoldState {
        let width = Double(proxy.size.width), height = Double(proxy.size.height)
        let band = proxy.reservedRegions(kind: .division, options: [.includeInactive])
            .lazy
            .compactMap { region in
                FoldRules.validate(
                    FoldBand(leading: Double(region.frame.minX),
                             trailing: Double(region.frame.maxX),
                             isActive: region.isActive),
                    width: width, height: height,
                    regionTop: Double(region.frame.minY),
                    regionBottom: Double(region.frame.maxY))
            }
            .first
        return FoldState(band: band, width: width)
    }
}
#endif

extension View {
    /// Publish the open iPhone Duo's fold to everything below (PRD-37).
    func readsFold() -> some View { modifier(FoldReader()) }

    /// Confine a page to the pane before the fold; identity without one.
    func inLeadingFoldPane() -> some View { modifier(LeadingFoldPane()) }
}

private struct LeadingFoldPane: ViewModifier {
    @Environment(\.foldBand) private var band

    func body(content: Content) -> some View {
        if let band {
            content
                .frame(width: CGFloat(band.leading))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}
```

- [ ] **Step 2: Wire it at the root.** In `RootView.body` (`NineApp.swift`), add `.readsFold()` as the last modifier before `#if os(macOS)` (after `.onAppear { AppDependencyManager… }`), with this comment:

```swift
        // PRD-37. Outermost on purpose: the overlays above are siblings of the
        // view an environment value is set on (see the Mac tutorial note below),
        // so the fold has to be published from outside all of them.
        .readsFold()
```

- [ ] **Step 3: Build all three platforms with both toolchains**

```bash
cd /Users/aquilops/nine/nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
done
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'generic/platform=iOS Simulator' -derivedDataPath build271 build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: four `BUILD SUCCEEDED`. With 26.6 the probe is compiled out (`canImport` false); with 27.1 it is in.

- [ ] **Step 4: Prove the probe sees the fold.** Temporarily add `.onChange(of: state) { print("FOLD", $1) }` inside `FoldReader`, run the 27.1 build on `Nine-Duo-Probe` (`xcrun simctl launch --console-pty …`), ask the operator to set Open and then Partially Open in Device Hub, and confirm `FOLD FoldState(band: Optional(…leading: 455.5, trailing: 495.5, isActive: false…), width: 867.0)` then `isActive: true`, then `band: nil` after Closed. Remove the print.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add nine/Sources/App/FoldReader.swift nine/Sources/App/NineApp.swift
git commit -m "PRD-37: read the fold once at the root, behind an SDK-version guard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: CouchKit — a trailing panel that fits the right pane

**Files:**
- Modify: `couchkit/Sources/CouchKit/GlassComponents.swift` (`GlassSheet.trailingPanel`, new environment key)
- Modify: `couchkit/API.md` (GlassSheet entry)

**Interfaces:**
- Produces: `public extension EnvironmentValues { var couchPanelWidth: CGFloat? }` (default `nil`). `GlassSheet`'s trailing panel uses `couchPanelWidth ?? 380`.

- [ ] **Step 1: Add the key** inside the file's existing `#if os(tvOS) || os(iOS) || os(macOS) || os(watchOS)` gate, just above `// MARK: - GlassSheet`:

```swift
/// The width a `GlassSheet` trailing panel takes, when the host knows better
/// than 380 — Nine's open iPhone Duo, whose right pane is 339.5pt (PRD-37).
/// `nil` everywhere else, which is today's panel exactly.
private struct CouchPanelWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    public var couchPanelWidth: CGFloat? {
        get { self[CouchPanelWidthKey.self] }
        set { self[CouchPanelWidthKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Use it.** In `GlassSheet`, add `@Environment(\.couchPanelWidth) private var panelWidth` beside the size-class property (outside any `#if`), and in `trailingPanel` change `.frame(maxWidth: 380, maxHeight: .infinity)` to:

```swift
                    .frame(maxWidth: panelWidth ?? 380, maxHeight: .infinity)
```

- [ ] **Step 2b: Nine publishes it.** In `nine/Sources/App/FoldReader.swift` (Task 4), add directly after `.environment(\.foldBand, state.band)`:

```swift
            // CouchKit's GlassSheet sizes its trailing panel from this; on the
            // open Duo that is the right pane, 339.5pt, leading edge at 511.5.
            .environment(\.couchPanelWidth, state.band.map {
                CGFloat(FoldRules.panelWidth(width: state.width, band: $0))
            })
```

- [ ] **Step 3: Record the contract.** In `couchkit/API.md`, under `public struct GlassSheet…`, add:

```markdown
extension EnvironmentValues { public var couchPanelWidth: CGFloat? }  // trailing panel width; nil = 380 (PRD-37)
```

- [ ] **Step 4: Test and build**

Run: `cd /Users/aquilops/nine/couchkit && swift test 2>&1 | tail -3` → passes. Then rebuild the four Nine targets from Task 4 Step 3 → `BUILD SUCCEEDED` ×4.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add couchkit/Sources/CouchKit/GlassComponents.swift couchkit/API.md
git commit -m "CouchKit: couchPanelWidth lets a host size GlassSheet's trailing panel (PRD-37)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The game screen's spread

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift` — the game `body` (`:977-1004`), `ChromeInsets` (`:1107-1139`), `chromed(…)` (`:1531`), `boardArea(side:inset:)` (`:2799`) and `roseLens(side:inset:rose:)` (`:3082`), `statsDrawer` / `debriefPanel` (`:2722`, `:2760`); new `spreadView(_:in:)` beside `draftingTable`.

**Interfaces:**
- Consumes: `\.foldBand`, `\.couchPanelWidth`, `BoardCompositionRules.resolve(…fold:)`, `Spread`, `RoseLens(…crease:)`.
- Produces: `spreadView(_ spread: Spread, in size: CGSize) -> some View`; `chromed(_:insets:revealHeight:controlBarReserve:chipOffset: CGFloat = 0)`; `boardArea(side:inset:crease: Double? = nil)`.

- [ ] **Step 1: Read the fold in the game view.** Add `@Environment(\.foldBand) private var foldBand` and `@Environment(\.couchPanelWidth) private var panelWidth` to the game screen struct, and change the composition to:

```swift
            let composition = BoardCompositionRules.resolve(
                width: Double(geo.size.width), height: Double(geo.size.height), fold: foldBand)
            Group {
                if let spread = composition.spread {
                    spreadView(spread, in: geo.size)
                } else if let table = composition.table {
                    draftingTable(table, in: geo.size)
                } else {
                    boardColumn(side: CGFloat(composition.boardSide), in: geo.size)
                }
            }
```

- [ ] **Step 2: Chips can move.** Add `chipOffset: CGFloat = 0` as `chromed`'s last parameter and apply `.offset(x: chipOffset)` to the toast, tip, completion-chip, auto-notes-chip and top-chip overlays only (not the debrief grabber or panel):

```swift
            .overlay(alignment: .bottom) { toastView.padding(.bottom, insets.chip).offset(x: chipOffset) }
            .overlay(alignment: .bottom) { tipView.padding(.bottom, insets.chip).offset(x: chipOffset) }
            .overlay(alignment: .bottom) { completionChip.padding(.bottom, insets.completion).offset(x: chipOffset) }
            .overlay(alignment: .bottom) { autoNotesChipView.padding(.bottom, insets.chip).offset(x: chipOffset) }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    composingChip
                    parlorRow
                }
                .padding(.top, insets.top)
                .offset(x: chipOffset)
            }
```

- [ ] **Step 3: The crease reaches the rose.** Add `crease: Double? = nil` to `boardArea(side:inset:)` and to `roseLens(side:inset:rose:)`, pass it through from `boardArea` to every `roseLens(…)` call inside it, and in `roseLens` forward it: `RoseLens(cursor: cursor, side: Double(side), inset: Double(inset), pencil: rose.pencil, scale: RoseLens.scale(forSide: Double(side)), crease: crease)`. Existing callers pass nothing.

- [ ] **Step 4: Add `spreadView`** after `draftingTable(_:in:)`:

```swift
    /// PRD-37: the open iPhone Duo, laid out as a book. The crease falls on
    /// the board's own thick rule (after column 6 on the Duo), the six controls
    /// stand on the leading page exactly as on the drafting table, and the
    /// trailing strip holds the readout and a 3×3 pad of 44pt keys. Flat and
    /// bent are the same layout — only the rose reads `isActive`.
    private func spreadView(_ spread: Spread, in size: CGSize) -> some View {
        let inset = CGFloat(BoardCompositionRules.boardInset)
        let side = CGFloat(spread.boardSide)
        let columnWidth = CGFloat(BoardCompositionRules.controlColumnWidth)
        let leadingGap = CGFloat(spread.boardLeft - spread.controlColumnX) - inset - columnWidth
        let trailingGap = CGFloat(spread.padX - spread.boardLeft) - side - inset
        let outer = CGFloat(BoardCompositionRules.outerPadding)
        let crease = (foldBand?.isActive ?? false) ? spread.crease - spread.boardLeft : nil
        return HStack(spacing: 0) {
            controlColumn
                .frame(width: columnWidth)
                .frame(maxHeight: .infinity)
            Color.clear.frame(width: leadingGap)
            chromed(
                boardArea(side: side, inset: inset, crease: crease)
                    .frame(maxHeight: .infinity),
                insets: .table,
                revealHeight: size.height - 2 * outer,
                controlBarReserve: 0,
                chipOffset: CGFloat(spread.chipCentreOffset)
            )
            Color.clear.frame(width: trailingGap)
            VStack(spacing: Space.l) {
                railHeader
                Spacer(minLength: 0)
                digitPad(columns: 3, keyHeight: CGFloat(BoardCompositionRules.padKeyFloor))
                Spacer(minLength: 0)
            }
            .frame(width: CGFloat(spread.padWidth))
            .frame(maxHeight: .infinity)
        }
        .padding(.leading, CGFloat(spread.controlColumnX))
        .padding(.vertical, outer)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // No rail on a spread, so the stats keep the phone's pull-down — the
        // drawer itself presents in the right pane (see `statsDrawer`).
        .overlay(alignment: .top) { drawerGrabber }
        .overlay(alignment: .top) { statsDrawer }
        .simultaneousGesture(drawerRevealGesture)
    }
```

- [ ] **Step 5: Drawer and debrief present in the right pane.** In `statsDrawer`, replace `.frame(maxWidth: 480)` … `.padding(.horizontal, 10)` with a pane-aware frame, leaving every other modifier:

```swift
                StatsDrawerContent(model: model)
                    .padding(18)
                    .frame(maxWidth: panelWidth ?? 480)
                    .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: panelWidth == nil ? nil : .infinity,
                           alignment: .trailing)
                    .padding(.horizontal, panelWidth == nil ? 10 : FoldPanel.inset)
```

and in `debriefPanel`, replace `.padding(.horizontal, 10)` after `DebriefCardContent(…)` with:

```swift
                .frame(maxWidth: panelWidth)
                .frame(maxWidth: panelWidth == nil ? nil : .infinity, alignment: .trailing)
                .padding(.horizontal, panelWidth == nil ? 10 : FoldPanel.inset)
```

and add near the top of the file's private helpers: `private enum FoldPanel { static let inset = CGFloat(FoldRules.panelInset) }`. With `panelWidth == nil` each chain reduces to exactly its old modifiers' effect (`frame(maxWidth: nil)` is the identity).

- [ ] **Step 6: Build and look.** Build with 27.1 (Task 4 Step 3's last command), install on `Nine-Duo-Probe`, start a game, ask the operator for Open. Screenshot `--display=primary-1` and confirm against PRD-37 §4.2: board 550.5pt (1651.5px), crease on the thick rule after column 6, control column left, readout and 3×3 pad right, nothing crossing the crease except the board along its rule. Then Partially Open: identical layout; open the rose on a cell in column 8 and confirm the ring sits over columns 1–6. Then Closed: today's iPhone column. Look at every screenshot.

- [ ] **Step 7: Run the gate** — `swift test`, `couchkit swift test`, `strings.py --selftest-catalog && strings.py --audit` (0 new). Build tvOS and macOS (Task 4 Step 3) — `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
cd /Users/aquilops/nine && git add nine/Sources/App/TouchUI.swift
git commit -m "PRD-37: the game screen's spread on the open iPhone Duo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Coach and Why cards — the other pane, and the coach drags

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift` — `coachView` (`:3400`), `whyView` (`:3324`), `toggleCoach` / `dismissCoach` (`:3358-3372`), the `.overlay { coachView }` / `.overlay { whyView }` call sites (`:995-996`).

**Interfaces:**
- Consumes: `FoldRules.cardPane(for:spread:)`, `FoldPane`, `CoachFocus(advice)`, `Spread`.
- Produces: `coachView(spread: Spread?)`, `whyView(spread: Spread?)`; `@State coachDragOffset: CGSize`; `@GestureState coachDragLive: CGSize`.

This spends 1.2's one new input concept (PRD-37 §4.5). Duo-open only.

- [ ] **Step 1: Pass the spread to the overlays.** At `:995-996`:

```swift
            .overlay { coachView(spread: composition.spread, width: geo.size.width) }
            .overlay { whyView(spread: composition.spread, width: geo.size.width) }
```

- [ ] **Step 2: A pane frame helper**, beside `spreadView`:

```swift
    /// A card's frame on the open Duo: its pane, less a 16pt gutter each side,
    /// no wider than the card's own 360pt. Nil without a spread.
    private func cardPaneFrame(_ pane: FoldPane, in width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard let band = foldBand else { return nil }
        let paneX = pane == .leading ? 0 : CGFloat(band.trailing)
        let paneWidth = pane == .leading ? CGFloat(band.leading) : width - CGFloat(band.trailing)
        let cardWidth = min(360, paneWidth - 32)
        return (paneX + (paneWidth - cardWidth) / 2, cardWidth)
    }
```

- [ ] **Step 3: The coach.** Add the state:

```swift
    /// Where the player dragged the coach card (PRD-37 §4.5). Not persisted:
    /// every new hint starts in the pane opposite its cells.
    @State private var coachDragOffset: CGSize = .zero
    @GestureState private var coachDragLive: CGSize = .zero
```

Reset it in `toggleCoach()` right before `withAnimation(.couchFast) { coachAdvice = advice }` and in `dismissCoach()`: `coachDragOffset = .zero`.

Change `coachView` to `private func coachView(spread: Spread?, width containerWidth: CGFloat) -> some View` (keep `@ViewBuilder`) and replace the `CoachCardContent(…)` chain's horizontal placement:

```swift
                let focus = coachAdvice.flatMap(CoachFocus.init)
                let cells = (focus?.pattern ?? []) + (focus?.victims ?? []) + [focus?.target].compactMap { $0 }
                let paneFrame = spread.flatMap { cardPaneFrame(FoldRules.cardPane(for: cells, spread: $0),
                                                               in: containerWidth) }
                CoachCardContent(
                    advice: coachAdvice,
                    accent: accent,
                    actionTitle: coachAdvice.actionTitle(autoNotes: model.autoNotes)
                ) {
                    if case .step(let step) = coachAdvice { model.applyCoachStep(step) }
                    dismissCoach()
                }
                .frame(width: paneFrame?.width)
                .padding(.horizontal, paneFrame == nil ? 20 : 0)
                .frame(maxWidth: paneFrame == nil ? nil : .infinity, alignment: .leading)
                .padding(.leading, paneFrame?.x ?? 0)
                .padding(model.prefs.controlsAtBottom ? .top : .bottom, 8)
                .offset(paneFrame == nil ? .zero : CGSize(
                    width: coachDragOffset.width + coachDragLive.width,
                    height: coachDragOffset.height + coachDragLive.height))
                .gesture(coachDrag, including: paneFrame == nil ? .none : .all)
                .transition(.opacity.combined(
                    with: .move(edge: model.prefs.controlsAtBottom ? .top : .bottom)
                ))
```

`containerWidth` is the game `GeometryReader`'s width, passed from the Step 1 call site. Add the gesture:

```swift
    /// Free drag; the card rests wherever it is dropped (the owner's choice
    /// over snapping). The lightbulb still toggles it away from anywhere.
    private var coachDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($coachDragLive) { value, live, _ in live = value.translation }
            .onEnded { value in
                coachDragOffset.width += value.translation.width
                coachDragOffset.height += value.translation.height
            }
    }
```

- [ ] **Step 4: The Why card** — same pane rule, no drag. In `whyView(spread:width:)`, the focus is the cursor: `let paneFrame = spread.flatMap { cardPaneFrame(FoldRules.cardPane(for: [cursor], spread: $0), in: width) }`, and on the `Group { … }` replace `.padding(.horizontal, 20)` with:

```swift
                .frame(width: paneFrame?.width)
                .padding(.horizontal, paneFrame == nil ? 20 : 0)
                .frame(maxWidth: paneFrame == nil ? nil : .infinity, alignment: .leading)
                .padding(.leading, paneFrame?.x ?? 0)
```

- [ ] **Step 5: Look.** On the open Duo: request a hint whose cells are in columns 1–6 → card in the right pane; one in columns 7–9 → left pane; drag it over the crease and release → it stays there; tap the lightbulb → it goes; request again → back in its default pane. Folded: today's card, not draggable (drag does nothing). Screenshot each, `--display=primary-1` when open.

- [ ] **Step 6: Gate + commit** — `swift test`, `strings.py --audit` (0 new), four builds; then:

```bash
cd /Users/aquilops/nine && git add nine/Sources/App/TouchUI.swift
git commit -m "PRD-37: coach and Why cards open opposite their cells; the coach drags on the open Duo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Shelf, channel, first run, tutorial and School

**Files:**
- Modify: `nine/Sources/App/TouchUI.swift` (shelf `body` `:72-73`, `shelfPair` `:318-364`)
- Modify: `nine/Sources/App/FirstRun.swift` (`FirstRunFlow.body` `:67-74`, `FirstFlickBeat.body`)
- Modify: `nine/Sources/App/TutorialView.swift` (`body` `:619-630`, new `spreadCards`)
- Modify: `nine/Sources/App/SchoolView.swift` (`body` `:216-227`)

**Interfaces:**
- Consumes: `resolveShelf(…fold:)`, `ShelfPair.trailingColumnWidth`, `\.foldBand`, `inLeadingFoldPane()`.

- [ ] **Step 1: Shelf and channel.** Add `@Environment(\.foldBand) private var foldBand` to the shelf view; pass `fold: foldBand` to `resolveShelf`. In `shelfPair(_:)`, add `let trailing = CGFloat(pair.trailingColumnWidth)` and use `trailing` (instead of `column`) in the **two** `.frame(width: column, alignment: .top)` calls that follow the *second* view of each `HStack` (the learn row on a channel page; `freePlaySection`/`parlorCard` otherwise). Equal widths everywhere but the Duo, so nothing else moves.

- [ ] **Step 2: First run.** In `FirstRunFlow.body`, `WelcomeCard(…)` gains `.inLeadingFoldPane()` before `.transition(.opacity)`. In `FirstFlickBeat`, add `@Environment(\.foldBand) private var foldBand` and wrap the body's `GeometryReader` content:

```swift
        GeometryReader { geo in
            if let band = foldBand {
                HStack(spacing: CGFloat(band.width)) {
                    GeometryReader { pane in
                        boardArea(geo: pane)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(Space.xxl)
                    .couchGlassElevated(
                        in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous),
                        isLight: tones.isLight)
                    .padding(Space.xl)
                    .frame(width: CGFloat(band.leading))
                    VStack(spacing: Space.l) {
                        header
                        instruction
                        Spacer(minLength: 0)
                        footer
                    }
                    .padding(Space.xxl)
                    .couchGlassElevated(
                        in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous),
                        isLight: tones.isLight)
                    .padding(Space.xl)
                    .frame(width: geo.size.width - CGFloat(band.trailing))
                }
            } else {
                // today's body, unchanged
                VStack(spacing: Space.l) {
                    header
                    instruction
                    boardArea(geo: geo)
                    footer
                }
                .padding(Space.xxl)
                .frame(maxWidth: 560)
                .couchGlassElevated(
                    in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous),
                    isLight: tones.isLight)
                .padding(Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
```

(keep every modifier that followed the original `GeometryReader` exactly where it was).

- [ ] **Step 3: Tutorial book spread.** Add `@Environment(\.foldBand) private var foldBand`; in `body`, replace `card(geo: geo, wide: wide)` with `if let band = foldBand { spreadCards(geo: geo, band: band) } else { card(geo: geo, wide: wide) }`, and add beside `card(geo:wide:)`:

```swift
    /// PRD-37: the open iPhone Duo. The practice board on the leading page,
    /// the words on the trailing one, the fold between them. The board sizes
    /// itself from its own pane's geometry, exactly as `card` sizes it from
    /// the window's.
    private func spreadCards(geo: GeometryProxy, band: FoldBand) -> some View {
        HStack(spacing: CGFloat(band.width)) {
            GeometryReader { pane in
                beat(geo: pane, wide: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Space.xl)
            .learnCard(in: cardShape, tones: tones)
            .padding(Space.l)
            .frame(width: CGFloat(band.leading))
            VStack(alignment: .leading, spacing: 0) {
                if isTouch {
                    header.simultaneousGesture(dismissDrag)
                } else {
                    header
                }
                instruction
                    .padding(.top, Space.m)
                Spacer(minLength: Rhythm.cluster)
                bottomBar
            }
            .padding(Space.xl)
            .learnCard(in: cardShape, tones: tones)
            .padding(Space.l)
            .frame(width: geo.size.width - CGFloat(band.trailing))
        }
        .offset(y: dragOffset)
    }
```

- [ ] **Step 4: School.** In `SchoolView.body`, append `.inLeadingFoldPane()` after the `Group`'s `.frame(maxWidth: .infinity, maxHeight: .infinity)` (inside the `ZStack`, so the scrim stays full-screen).

- [ ] **Step 5: Look.** On the open Duo (flat), screenshot `--display=primary-1`: home shelf (no card crosses x 475.5; columns 431.5 and 347.5), a channel page, the first-run welcome (erase the simulator's container to reset `welcomeSeen`, or use `ninestate.py`'s fresh seed), the first-flick beat, the tutorial (Settings ▸ How to play), School, Preferences (panel at x 511.5). Folded: each matches today's iPhone screenshot. Look at every one.

- [ ] **Step 6: Gate + commit** — `swift test`, `strings.py --audit` (0 new), four builds; then:

```bash
cd /Users/aquilops/nine && git add nine/Sources/App
git commit -m "PRD-37: shelf, channel, first run, tutorial and School on the open Duo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Harnesses — runtime pin, re-slim, Duo devices, posture gate

**Files:**
- Modify: `nine/scripts/simrig.py`, `shotlist.py`, `ax-snapshot.py`, `contrast-harness.py`, `loc-harness.py`

**Interfaces:**
- Produces (`simrig`): `ios_runtime(version=None)`, `reslim(udid)`, `require_posture(udid, posture)`, `screenshot_display(posture)`, `prepare_simulator(…, slim=None)`; constants `DUO = "iPhone Duo"`, `DUO_DISPLAY_OPEN = "primary-1"`.

- [ ] **Step 1: `simrig.py`** — add after `newest_ios_runtime()`:

```python
import os
import shutil

DUO = "iPhone Duo"
# Open, the Duo draws on its inner panel; the outer `primary` panel is dark.
# `simctl io screenshot` defaults to `primary`, so every open capture names it.
DUO_DISPLAY_OPEN = "primary-1"


def ios_runtime(version=None):
    """The runtime to boot: `version` ("26.5", "27.1") or NINE_SIM_RUNTIME,
    else the newest. **Pin it for every baseline lane**: the baselines record
    their runtime, and installing a newer one must not quietly move them."""
    version = version or os.environ.get("NINE_SIM_RUNTIME")
    if not version:
        return newest_ios_runtime()
    data = json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"]))
    ios = [r for r in data["runtimes"]
           if r.get("isAvailable") and r.get("platform") == "iOS"]
    match = [r for r in ios
             if r["version"] == version or r["version"].startswith(version + ".")]
    if not match:
        sys.exit("iOS %s simulator runtime not installed (have: %s)"
                 % (version, ", ".join(r["version"] for r in ios)))
    return match[-1]


def reslim(udid):
    """Erase and create bring a simulator back stock (~/.claude/CLAUDE.md).
    Nine waits on Game Center at launch, so `gamed` stays. Off on hosts without
    simslim (CI) and when NINE_SIMSLIM=0."""
    if shutil.which("simslim") is None or os.environ.get("NINE_SIMSLIM") == "0":
        return
    run(["simslim", "on", udid, "--keep", "com.apple.gamed"], check=False, capture=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture=False)


def screenshot_display(posture):
    return DUO_DISPLAY_OPEN if posture == "open" else None


def require_posture(udid, posture):
    """No tool can fold the simulator (PRD-37 §1.6): Device Hub's three posture
    buttons are the only control. Ask the operator, once per run — posture
    survives relaunch."""
    if not sys.stdin.isatty():
        sys.exit("the Duo %s lane needs a person to set Device Hub's posture; "
                 "run it from a terminal" % posture)
    label = {"open": "Open", "closed": "Closed"}[posture]
    answer = input("Set Device Hub's posture for %s to %s (bottom toolbar), "
                   "then type '%s' and press Return: " % (udid, label, posture))
    if answer.strip().lower() != posture:
        sys.exit("posture not confirmed")
```

In `prepare_simulator`, add a `slim=None` parameter and, right after `bootstatus`, `if slim is not False: reslim(udid)` — only when the simulator was just created or erased (track a `fresh` flag set in those two branches).

- [ ] **Step 2: `shotlist.py`** — add to `DEVICES`:

```python
    # PRD-37. One simulator, two postures: Device Hub sets the posture and it
    # survives relaunch, so each lane asks for it once.
    "duo-folded": dict(device_type="iPhone Duo", sim_name="Nine-Shotlist-Duo",
                       scale=3, runtime="27.1", posture="closed"),
    "duo-open": dict(device_type="iPhone Duo", sim_name="Nine-Shotlist-Duo",
                     scale=3, runtime="27.1", posture="open"),
```

Add `--runtime`; in `main` use `simrig.ios_runtime(args.runtime or dev.get("runtime"))`; after install, `if dev.get("posture"): simrig.require_posture(udid, dev["posture"])`; and in every `simctl io … screenshot` call add `["--display=" + d]` when `simrig.screenshot_display(dev.get("posture"))` returns `d`. Update the `DEVICES` comment ("Two devices, deliberately not five") to name the Duo lanes and why they are separate.

- [ ] **Step 3: `ax-snapshot.py`, `contrast-harness.py`, `loc-harness.py`** — each gains:

```python
    parser.add_argument("--device", default="iphone", choices=["iphone", "duo-folded", "duo-open"],
                        help="iphone keeps today's baselines and paths byte for byte")
    parser.add_argument("--runtime", default=None, help="pin the iOS runtime (e.g. 26.5, 27.1)")
```

mapping `iphone → ("iPhone 17 Pro", None, <today's baseline dir>)` and `duo-* → ("iPhone Duo", posture, <baseline dir>/<device>)`; the `DEVICE_TYPE` module constant becomes the resolved value; `simrig.ios_runtime(args.runtime)` replaces `simrig.newest_ios_runtime()`; `require_posture` after install for Duo lanes; screenshots pass the display. In `contrast-harness.py`, `SCREEN_POINT_WIDTH` becomes a per-device value: `{"iphone": 402.0, "duo-folded": 466.0, "duo-open": 951.0}` (the `Frame.__init__` check already validates it against the real image). The baseline header line keeps its format, so `iphone` output is byte-identical.

- [ ] **Step 4: Prove `iphone` is unchanged.** On Xcode 26.6: `python3 scripts/ax-snapshot.py --runtime 26.5` → `all accessibility trees match their baselines`; same for the contrast and loc harnesses in verify mode. Run once with `NINE_SIMSLIM=0` and once slim; if the slim run differs, record that in DEVIATIONS and default `NINE_SIMSLIM` to 0 for baseline lanes.

- [ ] **Step 5: Commit**

```bash
cd /Users/aquilops/nine && git add nine/scripts
git commit -m "PRD-37: harnesses pin their runtime, re-slim, and learn the Duo's two postures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: CI on Xcode 27.1, and the baselines' runtime move

**Files:**
- Modify: `.github/workflows/nine-engine.yml`, `nine-accessibility.yml`, `testflight-tvos.yml`
- Modify: `nine/Tests/AXBaselines/*.txt`, `nine/Tests/ContrastBaselines/matrix.txt`, `nine/Tests/LocBaselines/*` (re-recorded)

- [ ] **Step 1: Workflows.** In each of the three files, `runs-on: macos-latest` → `runs-on: xcode-27`, and replace the Xcode-selection `run:` block with:

```yaml
        run: |
          set -euo pipefail
          # Nine 1.2 needs the iOS 27.1 SDK (PRD-37 §5): the iPhone Duo's
          # hinge and fold APIs exist nowhere else. No fallback — a build made
          # with an older Xcode silently drops the Duo layout.
          XC=""
          for d in /Applications/Xcode_27.1*.app; do [ -e "$d" ] && XC="$d"; done
          if [ -z "$XC" ]; then
            echo "::error::Xcode 27.1 is not installed on this runner (actions/runner-images#14850). Installed:"
            ls -d /Applications/Xcode*.app || true
            exit 1
          fi
          sudo xcode-select -s "$XC"
          xcodebuild -version
```

Rename the step to `Select Xcode 27.1`.

- [ ] **Step 2: Re-record the iPhone baselines on iOS 27.1 from `main`'s code.**

```bash
cd /Users/aquilops/nine && git worktree add ../nine-main-271 main
cd ../nine-main-271/nine && export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
cp ../../nine/nine/scripts/*.py scripts/   # the Task 9 harness, unchanged app code
python3 scripts/ax-snapshot.py --record --runtime 27.1
python3 scripts/contrast-harness.py --record --runtime 27.1
python3 scripts/loc-harness.py --record --runtime 27.1
cp -R Tests/AXBaselines Tests/ContrastBaselines Tests/LocBaselines ../../nine/nine/Tests/
cd ../../nine && git worktree remove ../nine-main-271 --force
```

Read the diff: every hunk should be the `runtime:` header or a change attributable to iOS 27.1 itself. List any non-header hunks in the commit message.

- [ ] **Step 3: Commit, separately from any feature code**

```bash
git add nine/Tests/AXBaselines nine/Tests/ContrastBaselines nine/Tests/LocBaselines .github/workflows
git commit -m "CI on Xcode 27.1 (fails loudly without it); baselines re-recorded on iOS 27.1 from main's code

No app code in this commit: the baselines are main@9058cb1's output on the
iOS 27.1 runtime, so the runtime move and PRD-37 never share a diff.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Prove it — zero change elsewhere, the Duo on screen, the record

**Files:**
- Create: `nine/Tests/AXBaselines/duo-folded/`, `duo-open/` (and the contrast/loc equivalents if their lanes run on the Duo)
- Modify: `nine/DEVIATIONS.md`, `nine/PRD-37.md` (Status)

- [ ] **Step 1: Zero change on Xcode 26.6 / iOS 26.5.** Check out the commit *before* Task 10 into a worktree (it still has the 26.5 baselines), build the branch app with 26.6, and run `ax-snapshot.py --runtime 26.5 --app <branch Nine.app>`, contrast and loc in verify mode → all match byte for byte.

- [ ] **Step 2: Zero change on Xcode 27.1 / iOS 27.1.** On the branch, `DEVELOPER_DIR=…27.1… python3 scripts/ax-snapshot.py --runtime 27.1` (and contrast, loc) → all match the baselines Task 10 recorded from `main`.

- [ ] **Step 3: iPhone and iPad screenshots.** `shotlist.py --device both --appearance both --runtime 26.5` for `main` (worktree) and the branch, into two directories; compare each pair with a pixel diff (tolerance for Liquid Glass's live blur) and look at every pair side by side. Any difference beyond blur noise is a bug.

- [ ] **Step 4: The Duo lanes.** `DEVELOPER_DIR=…27.1… python3 scripts/shotlist.py --device duo-folded --appearance both` and `--device duo-open` (the operator sets posture when asked). Then `ax-snapshot.py --device duo-open --record` and `--device duo-folded --record`. If `sim-use describe-ui` returns nothing on the Duo (known issue 187148389), stop the AX lane there, keep its output, and record it in DEVIATIONS. Look at every screenshot against PRD-37 §4.

- [ ] **Step 5: Bent.** Operator sets Partially Open; capture the game (rose open on columns 7–9), Preferences and the home shelf. Identical to flat except the rose; look at each.

- [ ] **Step 6: Fold mid-game (Review Focus 3).** Start a board, place five digits, open the rose; operator folds, then unfolds. Screenshot after each: entries, cursor and clock preserved, rose closed or on the board.

- [ ] **Step 7: The record.** Add a dated `DEVIATIONS.md` section, `## PRD-37 — the spread (2026-10-14)`, with the measured facts that differ from the spec, the posture-needs-a-person limitation, the AX lane's outcome on the Duo, the tutorial board's measured size, and anything Task 9 Step 4 found. Set PRD-37's Status to `Implemented`.

- [ ] **Step 8: Final gate** — `cd nine && swift test`, `cd couchkit && swift test`, `cd nine && python3 scripts/strings.py --selftest-catalog && python3 scripts/strings.py --audit` (0 new); all four builds on 26.6 and the iOS build on 27.1.

- [ ] **Step 9: Commit, push, PR**

```bash
cd /Users/aquilops/nine && git add nine/Tests nine/DEVIATIONS.md nine/PRD-37.md
git commit -m "PRD-37: Duo baselines, the record, status Implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin claude/nine-duo-prd37
```

Write the PR body to `/private/tmp/…/scratchpad/pr37-body.md` with exactly these sections, filled from this run's own output (no claim without its command), then `gh pr create --base main --title "Nine 1.2: the spread — a bespoke iPhone Duo layout (PRD-37)" --body-file <that file>`:

1. **What** — two sentences and a link to `nine/PRD-37.md`.
2. **Zero change elsewhere** — the Task 11 Step 1 and Step 2 commands and their final lines (`all accessibility trees match their baselines`, contrast/loc equivalents), and the Step 3 pixel-diff summary.
3. **The Duo** — the screenshots from Steps 4–6 (attach), one line each.
4. **CI** — "Checks fail until actions/runner-images#14850 deploys Xcode 27.1 to the `xcode-27` image; that is by design (PRD-37 §5)." and "Merging runs `beta_all`: every platform's TestFlight build will be made with Xcode 27.1."
5. **Not done** — PRD-37 §7, verbatim.
6. The attribution line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

Then bind the PR (`mcp__ccd_pr__bind_pr`) and report CI honestly: red until GitHub deploys Xcode 27.1, by design.
