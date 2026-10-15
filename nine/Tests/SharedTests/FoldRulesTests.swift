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

    /// What the root publishes. The panel width rides only on a band that
    /// also yields a spread, and with no band the reading is the reader's
    /// initial state — so a resize on any other device writes nothing.
    func testTheRootPublishesAPanelWidthOnlyWithASpread() {
        let open = FoldRules.reading(Self.duoBand, width: Self.openWidth, height: Self.openHeight)
        XCTAssertEqual(open.band, Self.duoBand)
        XCTAssertEqual(open.panelWidth ?? 0, 339.5, accuracy: 0.001)

        XCTAssertEqual(FoldRules.reading(nil, width: Self.openWidth, height: Self.openHeight), .none)
        XCTAssertEqual(FoldRules.reading(nil, width: 402, height: 874), FoldReading.none)

        // A band that validates but is too short for any spread: the shelf may
        // still use the band, and no sheet is narrowed for a board that is
        // not there.
        let short = 200.0
        XCTAssertNotNil(FoldRules.validate(Self.duoBand, width: Self.openWidth, height: short,
                                           regionTop: 0, regionBottom: short))
        XCTAssertNil(FoldRules.spread(width: Self.openWidth, height: short, band: Self.duoBand))
        let squat = FoldRules.reading(Self.duoBand, width: Self.openWidth, height: short)
        XCTAssertEqual(squat.band, Self.duoBand)
        XCTAssertNil(squat.panelWidth)
    }

    /// A book spread's practice board fills its page. The page is already
    /// the card's content box, so the card's gutters are not taken off twice
    /// (measured on device: both spreads drew the 200pt floor's neighbourhood).
    /// Tutorial page on the Duo: 455.5 − 2×16 − 2×20 = 383.5 wide, 563 tall,
    /// glass inset 8. First flick: 455.5 − 2×20 − 2×28 = 359.5 × 539, inset 10.
    func testASpreadPageBoardFillsItsPage() {
        XCTAssertEqual(FoldRules.pageBoardSide(width: 383.5, height: 563, inset: 8), 367.5, accuracy: 0.001)
        XCTAssertEqual(FoldRules.pageBoardSide(width: 359.5, height: 539, inset: 10), 339.5, accuracy: 0.001)
        XCTAssertEqual(FoldRules.pageBoardSide(width: 300, height: 180, inset: 8), 200)  // the floor
    }

    /// Measured on device: a leading-pane coach card spanning the whole pane
    /// (x 47.75–407.75) covered the control column and its Back button. The
    /// leading pane a card may use starts past the control column and its
    /// gutter (x 96), so the card sits over board columns 1–6 only; the
    /// trailing pane is the right pane, as the sheets take it.
    func testACardNeverCoversTheControlColumn() throws {
        let s = try XCTUnwrap(FoldRules.spread(width: Self.openWidth, height: Self.openHeight,
                                               band: Self.duoBand))
        let leading = FoldRules.cardFrame(.leading, width: Self.openWidth, band: Self.duoBand, spread: s)
        XCTAssertEqual(leading.x, 112, accuracy: 0.001)
        XCTAssertEqual(leading.width, 327.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(leading.x, s.controlColumnX + BoardCompositionRules.controlColumnWidth)
        XCTAssertLessThanOrEqual(leading.x + leading.width, Self.duoBand.leading)

        let trailing = FoldRules.cardFrame(.trailing, width: Self.openWidth, band: Self.duoBand, spread: s)
        XCTAssertEqual(trailing.x, 511.5, accuracy: 0.001)
        XCTAssertEqual(trailing.width, 339.5, accuracy: 0.001)
    }

    func testACardOpensOppositeTheCellsItDiscusses() throws {
        let s = try XCTUnwrap(FoldRules.spread(width: Self.openWidth, height: Self.openHeight,
                                               band: Self.duoBand))
        XCTAssertEqual(FoldRules.cardPane(for: [3 * 9 + 1], spread: s), .trailing)      // r4c2
        XCTAssertEqual(FoldRules.cardPane(for: [3 * 9 + 7], spread: s), .leading)       // r4c8
        XCTAssertEqual(FoldRules.cardPane(for: [0, 1, 8], spread: s), .trailing)        // majority left
        XCTAssertEqual(FoldRules.cardPane(for: [], spread: s), .trailing)               // nothing to cover
    }

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
