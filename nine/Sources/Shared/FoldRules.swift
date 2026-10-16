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

/// What `FoldReader` publishes to everything below the root.
public struct FoldReading: Equatable, Sendable {
    public let band: FoldBand?
    public let panelWidth: Double?

    public static let none = FoldReading(band: nil, panelWidth: nil)
}

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

    /// What the root publishes for one window: the validated band, and the
    /// trailing panel's width only when that band also yields a spread — a
    /// sheet is narrowed to the right pane because the board fills the left.
    /// With no band it is `.none`, the reader's initial state, so a resize on
    /// a window without a fold writes nothing.
    public static func reading(_ band: FoldBand?, width: Double, height: Double) -> FoldReading {
        guard let band else { return .none }
        let spreads = spread(width: width, height: height, band: band) != nil
        return FoldReading(band: band,
                           panelWidth: spreads ? panelWidth(width: width, band: band) : nil)
    }

    /// The practice board on a book spread's leading page (the tutorial, the
    /// first flick): the page's content box less the board's glass inset, no
    /// smaller than the 200pt every practice board keeps. `width` and
    /// `height` are the page itself — its card's padding is already gone.
    public static func pageBoardSide(width: Double, height: Double, inset: Double) -> Double {
        max(200, min(width, height) - 2 * inset)
    }

    /// The widest a coach or Why card gets, as on every other device.
    public static let cardMaxWidth = 360.0

    /// Where a coach or Why card opens on the spread: centred in `pane`, 16pt
    /// clear of its edges, no wider than `cardMaxWidth`. The leading pane
    /// starts past the control column and its gutter, because the card must
    /// not cover the column's buttons (measured: a pane-wide card hid Back).
    public static func cardFrame(_ pane: FoldPane, width: Double, band: FoldBand,
                                 spread: Spread) -> (x: Double, width: Double) {
        typealias R = BoardCompositionRules
        let paneX = pane == .leading
            ? spread.controlColumnX + R.controlColumnWidth + R.gutter
            : band.trailing
        let paneEnd = pane == .leading ? band.leading : width
        let cardWidth = min(cardMaxWidth, paneEnd - paneX - 2 * panelInset)
        return (paneX + (paneEnd - paneX - cardWidth) / 2, cardWidth)
    }

    /// The pane a card about `cells` opens in: whichever holds fewer of them,
    /// so the card does not cover what it is talking about. Ties and empty
    /// lists go to the trailing pane, where the spread's pad already is.
    public static func cardPane(for cells: [Int], spread: Spread) -> FoldPane {
        let leading = cells.filter { $0 % 9 < spread.ruleAfterColumn }.count
        return leading >= cells.count - leading ? .trailing : .leading
    }
}
