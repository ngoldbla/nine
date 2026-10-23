// VisionBoardScreen.swift — the board, floating alone in the room.
//
// The default state is zero visible UI (README, rule one): a slab of glass
// with 81 cells on it. Look at a cell and the system lights it; pinch and two
// ornaments arrive — the keypad on the trailing edge, New Game below — and
// pinching the cell again sends them away. On the solve the board rises toward
// the player while the Afterglow runs across it and sparks lift off the
// winning digit.
#if os(visionOS)
import SwiftUI
import CouchKit

/// The visionOS board's fixed geometry, in points. 80pt cells clear the 60pt
/// eye-target floor with room to spare, and a fixed board is one size of
/// everything to get right instead of a range.
enum VisionBoardMetrics {
    static let side: CGFloat = 720
    static let inset: CGFloat = 28
    static var card: CGFloat { side + inset * 2 }
    static var cell: CGFloat { side / 9 }
    /// How far the solved board rises toward the player.
    static let lift: CGFloat = 48
}

struct VisionBoardScreen: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { model.accent.color(isLight: false) }
    private var chromeShown: Bool { model.cursor != nil && !model.isSolved }

    var body: some View {
        ZStack {
            if let game = model.game {
                board(game)
            } else {
                ProgressView()
                    .frame(width: VisionBoardMetrics.card, height: VisionBoardMetrics.card)
                    .glassBackgroundEffect(
                        in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            }
        }
        .environment(\.nineTheme, .auto)
        .tint(accent)
        .ornament(
            visibility: chromeShown ? .visible : .hidden,
            attachmentAnchor: .scene(.trailing),
            contentAlignment: .leading
        ) {
            VisionKeypad()
                .padding(.leading, 24)
        }
        .ornament(
            visibility: chromeShown || model.isSolved ? .visible : .hidden,
            attachmentAnchor: .scene(.bottom),
            contentAlignment: .top
        ) {
            NewBoardMenu()
                .padding(.top, 24)
        }
        .animation(.couchFast, value: chromeShown)
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scene(active: phase == .active)
        }
    }

    private func board(_ game: NineGame) -> some View {
        let solvedAt = model.solvedAt.flatMap { $0 == .distantPast ? nil : $0 }
        let rising = model.isSolved && !reduceMotion
        return ZStack {
            BoardView(
                game: game,
                cursor: model.cursor ?? -1,
                accent: accent,
                showErrors: true,
                solvedAt: model.solvedAt,
                roseOpen: false,
                previewDigit: nil,
                previewPencil: false,
                highlightDigit: model.highlightDigit,
                waveOrigin: solvedAt == nil ? nil : model.winningCell,
                side: VisionBoardMetrics.side,
                inset: VisionBoardMetrics.inset,
                axActions: axActions,
                lastEvent: model.lastEvent
            )
            if !model.isSolved {
                CellTargets { model.select($0) }
            }
            AfterglowSparks(
                trigger: reduceMotion ? nil : solvedAt,
                origin: model.winningCell,
                accent: accent)
        }
        .frame(width: VisionBoardMetrics.card, height: VisionBoardMetrics.card)
        // The trophy moment: the solved board comes forward to meet the
        // player. A gentle spring, and none at all under Reduce Motion — depth
        // that moves is the one motion a headset cannot let you look away from.
        .offset(z: rising ? VisionBoardMetrics.lift : 0)
        .animation(.spring(response: 0.9, dampingFraction: 0.7), value: rising)
    }

    /// VoiceOver, Switch Control and Voice Control drive the same model the
    /// pinch does, through the board's own 81-element tree (PRD-19).
    private var axActions: BoardAXActions {
        guard !model.isSolved else { return BoardAXActions() }
        var actions = BoardAXActions()
        actions.pencilMode = model.pencilMode
        actions.select = { cell in
            if model.cursor != cell { model.select(cell) }
        }
        actions.place = { digit, cell in
            if model.cursor != cell { model.select(cell) }
            model.enter(digit)
        }
        actions.note = { digit, cell in
            if model.cursor != cell { model.select(cell) }
            let was = model.pencilMode
            model.pencilMode = true
            model.enter(digit)
            model.pencilMode = was
        }
        actions.erase = { cell in
            if model.cursor != cell { model.select(cell) }
            model.erase()
        }
        return actions
    }
}

/// 81 invisible targets laid over the Canvas, one per cell, so the system can
/// draw its gaze highlight on the cell being looked at. The highlight is
/// rendered out of process — the app learns about a cell only when it is
/// pinched, never where the eyes rest.
///
/// Hidden from accessibility: the board's own synthetic tree already speaks
/// for every cell, and a second copy would read every cell twice.
private struct CellTargets: View {
    let onPinch: (Int) -> Void

    var body: some View {
        let unit = VisionBoardMetrics.cell
        let shape = RoundedRectangle(cornerRadius: unit * 0.2, style: .continuous)
        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { col in
                        Color.clear
                            .frame(width: unit, height: unit)
                            .contentShape(shape)
                            .contentShape(.hoverEffect, shape.inset(by: 4))
                            .hoverEffect(.highlight)
                            .onTapGesture { onPinch(row * 9 + col) }
                    }
                }
            }
        }
        .padding(VisionBoardMetrics.inset)
        .accessibilityHidden(true)
    }
}

/// New Game, by band. On a solved board it is the only chrome left in the
/// room, which is all the emphasis it needs — a prominent variant was tried
/// and a `Menu` on visionOS drew it identically, so it went rather than stay
/// as styling that does nothing.
private struct NewBoardMenu: View {
    @Environment(VisionModel.self) private var model

    var body: some View {
        Menu {
            ForEach(Difficulty.allCases, id: \.self) { band in
                Button(Strings.difficulty(band)) { model.compose(band) }
            }
        } label: {
            Label(Strings.string("menu.game.newGame"), systemImage: "square.grid.3x3")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 60)
        }
        .disabled(model.composing)
        .buttonStyle(.borderless)
        .buttonBorderShape(.capsule)
        .glassBackgroundEffect(in: Capsule())
    }
}
#endif
