// PadSession.swift — the controller-locked board grammar (PRD-5 §2.1, cut to
// the minimum by the tvOS input pass).
//
// A reference-type controller (not view `@State`) owns the pad-play state,
// because the gesture stream arrives from PadKit's reader — an external event
// source. GameScreen holds one in `@State` (the reference is stable across
// re-renders) and points `padReader.onGesture` at `handle(_:)`; every mutation
// flows through the same `AppModel` paths the remote and touch grammars use.
//
// Six jobs, the same six the Siri Remote does, one control each:
//   left stick / d-pad   move the cursor · in the rose, move the petal focus
//   Cross                open the rose · place the focused petal
//   Square               pencil mode on / off
//   Triangle             undo
//   Options (☰) / Create settings
//   Circle               Back: close the rose or panel · else arm, and a
//                        second Circle within 2.5 s saves and goes home
//
// Everything else was retired by the input pass, on purpose: the right-stick
// flick and R3, the L1/R1 empty-cell jumps, the L2/R2 peek, Triangle's
// same-number highlight (the cursor's own digit lights its kind, as on the
// remote) and Circle's hold-to-erase. Each was a second way to do something or
// a feature no beta player found; together they made a guide nobody could
// read from the sofa.
#if os(tvOS)
import SwiftUI
import CouchKit

@MainActor
@Observable
final class PadPlayController {
    @ObservationIgnored let model: AppModel
    @ObservationIgnored let haptics: ControllerHaptics

    /// The armed cell.
    var cursor = 40
    /// Square toggles pencil mode — the rose then writes corner notes.
    var pencilSticky = false
    /// Cross opens the rose; the stick or d-pad walks it and Cross places.
    var learningRose: RoseState?
    /// Options opened settings; while up, the pad drives the panel's focus and
    /// board gestures are parked.
    var showPrefs = false
    /// The glass toast shown after a Triangle undo.
    var undoToast: UndoToastState?

    /// Circle, meaning Back. GameScreen owns what Back does (the panel, the
    /// rose, the two-press exit), so the pad only reports it.
    @ObservationIgnored var onBack: (@MainActor () -> Void)?

    @ObservationIgnored private var undoToastClear: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        self.haptics = ControllerHaptics(provider: model.padReader.haptics)
        self.haptics.enabled = model.prefs.controllerHaptics
    }

    /// Mirror the "Controller haptics" pref (call when it or the screen changes).
    func syncHaptics() { haptics.enabled = model.prefs.controllerHaptics }

    /// The digit Cross would place, ghosted into the cell.
    var previewDigit: Int? {
        guard let learningRose else { return nil }
        return learningRose.focusedIndex + 1
    }

    /// Same-number highlight, the remote's way: the cursor's own digit.
    var highlightDigit: Int? {
        guard let digit = model.game?.entry(at: cursor), digit != 0 else { return nil }
        return digit
    }

    // MARK: - Gesture entry

    func handle(_ gesture: PadGesture) {
        guard model.game != nil, model.solvedAt == nil else { return }
        // With settings up the pad navigates the panel via the focus engine;
        // the settings button closes it, Circle is Back, the rest is parked.
        if showPrefs {
            switch gesture {
            case .button(.options), .button(.menu): showPrefs = false
            case .button(.circle): onBack?()
            default: break
            }
            return
        }
        switch gesture {
        case .move(let direction, _):
            move(direction)
        case .button(let button):
            press(button)
        case .flick, .flickAmbiguous, .buttonUp, .connect, .disconnect:
            // The right stick no longer places, and no button has a hold.
            break
        }
    }

    // MARK: - Movement

    private func move(_ direction: Direction4) {
        if var rose = learningRose {
            // The stick walks the petals too, one step per detent — a gentle
            // push is one petal, which is the only distance the rose has.
            rose.focusedIndex = RoseGeometry.moveFocus(rose.focusedIndex, direction)
            learningRose = rose
            return
        }
        let before = cursor
        cursor = BoardMetrics.moveCursor(cursor, direction, wrap: false)
        if cursor != before, boxIndex(cursor) != boxIndex(before) {
            haptics.detent()
        }
    }

    private func boxIndex(_ cell: Int) -> Int {
        let row = cell / 9, col = cell % 9
        return (row / 3) * 3 + col / 3
    }

    // MARK: - Placement

    private func commit(digit: Int) {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        if pencilSticky {
            guard game.entry(at: cursor) == 0 else { learningRose = nil; return }
            model.togglePencil(digit, at: cursor)
            haptics.placement()
        } else {
            model.place(digit, at: cursor)
            if model.solvedAt != nil {
                haptics.solve() // the full crescendo, in hand
            } else if model.prefs.errorHighlight, model.game?.isError(at: cursor) == true {
                haptics.error() // the soft double-knock, only when error highlight is on
            } else {
                haptics.placement() // the whisper tick
            }
        }
        learningRose = nil
    }

    // MARK: - Buttons

    private func press(_ button: PadButton) {
        switch button {
        case .cross:
            if let rose = learningRose {
                commit(digit: rose.focusedIndex + 1)
            } else {
                openRose()
            }
        case .circle:
            onBack?()
        case .square:
            pencilSticky.toggle()
        case .triangle:
            performUndo()
        case .options, .menu:
            learningRose = nil
            showPrefs = true
        case .r3, .l1, .r1, .l2, .r2:
            break
        }
    }

    private func openRose() {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        if pencilSticky, game.entry(at: cursor) != 0 { return } // notes need an empty cell
        learningRose = RoseState(pencil: pencilSticky)
    }

    /// Take back the last move with a glass toast (mirrors the remote's undo).
    private func performUndo() {
        guard let move = model.undoMove() else { return }
        haptics.placement()
        let next = UndoToastState(text: UndoPhrase.forMove(move))
        undoToast = next
        undoToastClear?.cancel()
        undoToastClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            if self?.undoToast?.id == next.id { self?.undoToast = nil }
        }
    }
}

// The reconnect veil is retired (PRD-5 revised): a controller drop mid-game now
// falls back to the remote grammar in place with a brief chip, timer running —
// see GameScreen.fallBackToRemote(). No pause, no modal freeze.
#endif
