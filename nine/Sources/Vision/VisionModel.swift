// VisionModel.swift — the whole of Nine's state on Vision Pro.
//
// Deliberately not `AppModel`, for the watch's reason (WatchModel.swift):
// `AppModel` owns `LibraryCloudStore`, which builds a `CKContainer(identifier:)`
// and traps on a binary without the CloudKit entitlement. Vision Pro ships
// local-only, so it gets the smallest model that can play: one board, the
// cursor, pencil mode, and the solve moment.
//
// Everything persisted is one top-level `CouchStored` key of its own that
// decodes tolerantly (EXECUTING-A-PRD §2).
#if os(visionOS)
import Foundation
import Observation
import SwiftUI
import CouchKit

/// Where the player left the board. One slot, because a Vision Pro session is
/// one board floating in a room — there is no shelf to come back to.
struct VisionSaveSlot: Codable, Sendable, Equatable {
    var game: NineGame?
    var cursor: Int?
    var difficulty: Difficulty?

    init() {}

    enum CodingKeys: String, CodingKey { case game, cursor, difficulty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try? c.decodeIfPresent(NineGame.self, forKey: .game) ?? nil
        cursor = try? c.decodeIfPresent(Int.self, forKey: .cursor) ?? nil
        // `try?` because a future band this build cannot name must not throw
        // the board away with it.
        difficulty = try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? nil
    }
}

@MainActor
@Observable
final class VisionModel {
    @ObservationIgnored private let slotStore =
        CouchStored(wrappedValue: VisionSaveSlot(), "nine.vision.board")

    private(set) var game: NineGame?
    private(set) var difficulty: Difficulty = .gentle
    private(set) var composing = false
    /// The selected cell, or nil. Nil is the resting state: no chrome at all.
    var cursor: Int?
    var pencilMode = false
    private(set) var solvedAt: Date?
    /// The winning placement — where the Afterglow and the sparks start.
    private(set) var winningCell: Int?
    /// The board's answer to the last move (settle, echo, shake).
    private(set) var lastEvent: (cell: Int, kind: CellEventKind, at: Date)?

    /// One accent, the shipped default. Vision Pro carries no KVS entitlement,
    /// so it cannot read the phone's published appearance; one fixed accent is
    /// less surface than a settings screen nobody asked for.
    let accent: AccentChoice = .glacier

    init() {
        let slot = slotStore.wrappedValue
        if var saved = slot.game {
            // A run still open at launch was left by a process that died, not
            // by an honest pause; nobody watched that gap, so it credits
            // nothing. The scene going active starts the clock again.
            if let since = saved.timer.runningSince {
                saved.timer.closeOpenRun(notLaterThan: since)
            }
            game = saved
            difficulty = slot.difficulty ?? .gentle
            cursor = slot.cursor.flatMap { (0..<81).contains($0) ? $0 : nil }
            if saved.isSolved {
                // Reopening a solved board shows it solved, without replaying
                // the celebration as if it had just happened.
                solvedAt = .distantPast
                cursor = nil
            }
        } else {
            compose(.gentle)
        }
        #if DEBUG
        stageForScreenshots()
        #endif
    }

    #if DEBUG
    /// Headless verification, the visionOS twin of `--debug-pad-gestures`: a
    /// simulator cannot be pinched from a script, so these stage the two
    /// states a screenshot has to see. `--vision-near-solve` fills every empty
    /// cell but one and selects it (the keypad is up); `--vision-solve` then
    /// places the last digit through `enter`, the same path a pinch takes.
    private func stageForScreenshots() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--vision-near-solve") || args.contains("--vision-solve"),
              var g = game else { return }
        let solution = g.puzzle.solution.cells
        let empty = (0..<81).filter { g.entry(at: $0) != solution[$0] }
        guard let last = empty.last else { return }
        for cell in empty.dropLast() { g.place(solution[cell], at: cell) }
        game = g
        solvedAt = nil
        cursor = last
        if args.contains("--vision-solve") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.enter(solution[last])
            }
        }
    }
    #endif

    var isSolved: Bool { solvedAt != nil }

    // MARK: - Boards

    func compose(_ band: Difficulty) {
        guard !composing else { return }
        composing = true
        let seed = UInt64.random(in: .min ... .max)
        Task.detached(priority: .userInitiated) { [weak self] in
            // Pure, Sendable, deterministic — safe off the main actor.
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: band)
            await MainActor.run {
                guard let self else { return }
                var fresh = NineGame(puzzle: puzzle)
                fresh.timer.start(at: Date())
                self.game = fresh
                self.difficulty = band
                self.solvedAt = nil
                self.winningCell = nil
                self.lastEvent = nil
                self.cursor = nil
                self.pencilMode = false
                self.composing = false
                self.persist()
            }
        }
    }

    // MARK: - Selection

    /// Pinching the selected cell again lets go of it — and with it the chrome.
    func select(_ cell: Int) {
        guard !isSolved, (0..<81).contains(cell) else { return }
        cursor = cursor == cell ? nil : cell
        persist()
    }

    /// The digit the board lights everywhere: whatever the cursor holds.
    var highlightDigit: Int? {
        guard let game, let cursor else { return nil }
        let digit = game.entry(at: cursor)
        return digit == 0 ? nil : digit
    }

    // MARK: - Moves

    /// A digit from the keypad: a note in pencil mode, otherwise a placement.
    /// Pressing the digit a cell already holds takes it back out, so the
    /// keypad alone can always undo its own last word.
    func enter(_ digit: Int) {
        guard var g = game, let cell = cursor, !isSolved, !g.isGiven(cell) else { return }
        let elapsed = g.timer.elapsed(at: Date())
        if pencilMode {
            guard g.togglePencil(digit, at: cell, elapsed: elapsed) else { return }
            game = g
            persist()
            return
        }
        if g.entry(at: cell) == digit {
            erase()
            return
        }
        guard g.place(digit, at: cell, elapsed: elapsed) else { return }
        game = g
        let wrong = g.isError(at: cell)
        lastEvent = (cell, wrong ? .error : .place, Date())
        if g.isSolved {
            finishSolve(at: cell)
        } else {
            persist()
        }
    }

    func erase() {
        guard var g = game, let cell = cursor, !isSolved,
              g.erase(at: cell, elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        lastEvent = (cell, .erase, Date())
        persist()
    }

    func undo() {
        guard var g = game, !isSolved,
              let move = g.undo(elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        cursor = move.cell
        persist()
    }

    var canUndo: Bool { !(game?.undoStack.isEmpty ?? true) && !isSolved }

    /// The keypad greys a digit once all nine are placed.
    func isDigitComplete(_ digit: Int) -> Bool { game?.isDigitComplete(digit) ?? false }

    // MARK: - Lifecycle

    /// The timer runs only while the window is in the room.
    func scene(active: Bool) {
        guard var g = game, !isSolved else { return }
        if active { g.timer.start(at: Date()) } else { g.timer.pause(at: Date()) }
        game = g
        persist()
        if !active { try? slotStore.flushNow() }
    }

    private func finishSolve(at cell: Int) {
        guard var g = game else { return }
        let now = Date()
        g.timer.pause(at: now)
        game = g
        winningCell = cell
        solvedAt = now
        cursor = nil
        pencilMode = false
        persist()
        try? slotStore.flushNow()
    }

    private func persist() {
        var slot = VisionSaveSlot()
        slot.game = game
        slot.cursor = cursor
        slot.difficulty = difficulty
        slotStore.wrappedValue = slot
    }
}
#endif
