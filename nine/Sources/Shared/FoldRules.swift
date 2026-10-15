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
