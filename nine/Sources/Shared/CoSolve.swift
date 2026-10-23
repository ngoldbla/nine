// CoSolve.swift — several people, one board, at once (Vision Pro SharePlay).
//
// A parlor (Parlor.swift) is N solitary boards that happen to be the same
// board; a duel (Duel.swift) is one board passed between two hands in turn.
// A co-solve is the third shape: one board, everybody's hands on it at the
// same time. It reuses both rather than standing beside them — the activity's
// payload is a `ParlorInvite` (the board is a pure function of its seed and
// band, so the grid never crosses the wire), the roster rides `ParlorEnvelope`,
// and who placed which digit is a `DuelState` over the move log, so the tint is
// `DuelTint`'s tested pair and the credits are `DuelCredits`.
//
// What neither of them has is a *move* on the wire, because neither ever
// needed one. That is this file, and it is small on purpose: one message type
// and the rule that makes every participant's board converge.
//
// **The rule is last-writer-wins per cell under a Lamport clock**, tie broken
// by author. Messages from one sender arrive in order, but two senders' do not
// arrive in the same order everywhere — two people placing in the same cell at
// the same moment would otherwise leave two different boards on two headsets
// and nobody would ever find out. With a total order on (clock, author), every
// participant keeps the same winner whatever order the messages came in.
//
// Digits only. Pencil notes stay on the headset that wrote them: they are one
// person's working, not the board's, and three people's notes in one cell is
// noise nobody can read.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// One participant setting one cell — a digit, or 0 for cleared.
public struct CoSolveMove: Codable, Equatable, Sendable {
    public let cell: Int
    /// 1–9, or 0 when the cell was erased (or an undo emptied it).
    public let digit: Int
    /// The sender's Lamport clock when it made the move.
    public let clock: Int
    public let author: UUID

    public init(cell: Int, digit: Int, clock: Int, author: UUID) {
        self.cell = cell
        self.digit = digit
        self.clock = clock
        self.author = author
    }

    /// Whether this move could be about a real cell at all. A move from a newer
    /// build, or a corrupted one, is dropped rather than applied somewhere odd.
    public var isWellFormed: Bool {
        (0..<81).contains(cell) && (0...9).contains(digit) && clock > 0
    }

    /// The total order every participant agrees on.
    func supersedes(_ other: CoSolveMove) -> Bool {
        if clock != other.clock { return clock > other.clock }
        return author.uuidString > other.author.uuidString
    }
}

/// Everything a participant has decided about the board, sent once to whoever
/// joins after the first move — the late joiner composes the same board from
/// the invite, then replays this.
public struct CoSolveSnapshot: Codable, Equatable, Sendable {
    public let moves: [CoSolveMove]

    public init(moves: [CoSolveMove]) { self.moves = moves }

    /// Tolerant: a snapshot that cannot be read is an empty one, and the next
    /// move corrects the board, rather than a thrown decode dropping the call.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moves = (try? c.decode([CoSolveMove].self, forKey: .moves)) ?? []
    }
}

/// The per-cell register. Pure, so convergence is tested here rather than on a
/// FaceTime call no simulator can place.
public struct CoSolveLedger: Equatable, Sendable {
    public private(set) var clock = 0
    /// The winning move per cell, for every cell anyone has touched.
    public private(set) var cells: [Int: CoSolveMove] = [:]

    /// This participant's own moves in the call, oldest first, each with the
    /// digit it replaced — what an undo of *your* moves walks back. The board's
    /// `NineGame.undoStack` cannot do this: it is everybody's.
    private var own: [OwnMove] = []

    private struct OwnMove: Equatable, Sendable {
        let clock: Int
        let cell: Int
        let before: Int
    }

    public init() {}

    /// A move made on this headset. Always wins locally — it is stamped past
    /// everything this participant has seen. `undoable` is false for the
    /// board a headset brings into the call (stamped so a late joiner gets
    /// it, not placed in the call) and for an undo itself, which is not redo.
    public mutating func stamp(cell: Int, digit: Int, author: UUID,
                               undoable: Bool = true) -> CoSolveMove {
        let before = cells[cell]?.digit ?? 0
        clock += 1
        let move = CoSolveMove(cell: cell, digit: digit, clock: clock, author: author)
        cells[cell] = move
        if undoable { own.append(OwnMove(clock: move.clock, cell: cell, before: before)) }
        return move
    }

    /// Whether `author` has a move still standing to take back.
    public func canUndo(author: UUID) -> Bool {
        own.contains { isStanding($0, author: author) }
    }

    /// Take back `author`'s latest move that nobody has since written over:
    /// the cell goes back to what it held before, as a new move stamped past
    /// everything seen, so every participant applies it like any other. A
    /// move somebody else has overwritten is not yours to undo any more and
    /// is skipped. Nil when nothing of yours is left.
    public mutating func undoLast(author: UUID) -> CoSolveMove? {
        while let last = own.popLast() {
            guard isStanding(last, author: author) else { continue }
            return stamp(cell: last.cell, digit: last.before, author: author, undoable: false)
        }
        return nil
    }

    private func isStanding(_ move: OwnMove, author: UUID) -> Bool {
        guard let current = cells[move.cell] else { return false }
        return current.clock == move.clock && current.author == author
    }

    /// A move from somebody else. Returns true when it changes the board, so
    /// the caller applies it; false when it lost to something already here.
    public mutating func apply(_ move: CoSolveMove) -> Bool {
        guard move.isWellFormed else { return false }
        clock = max(clock, move.clock)
        if let current = cells[move.cell], !move.supersedes(current) { return false }
        cells[move.cell] = move
        return true
    }

    /// The board so far, oldest first, for a late joiner.
    public var snapshot: CoSolveSnapshot {
        CoSolveSnapshot(moves: cells.values.sorted { $1.supersedes($0) })
    }
}

/// What a co-solve move did to the board — the answer the board draws.
public enum CoSolveLanding: Equatable, Sendable {
    case placed(wrong: Bool)
    case erased
}

/// Landing a move on a `NineGame`, with its attribution. Pure, so it is held
/// under `swift test` rather than only inside the visionOS-only model.
public enum CoSolveBoard {

    /// Land `move` through the board's own `place`/`erase` — so the move log,
    /// the settle and the shake are the board's — and credit it to `seat`.
    /// Nil when the move changes nothing (a given, or the digit already
    /// there); such a move opens no turn, so it can tint nothing.
    public static func land(_ move: CoSolveMove, seat: Int, on game: inout NineGame,
                            seats: inout DuelState?, elapsed: TimeInterval) -> CoSolveLanding? {
        guard move.isWellFormed, !game.isGiven(move.cell) else { return nil }
        let index = game.moveLog.count
        let changed = move.digit == 0
            ? game.erase(at: move.cell, elapsed: elapsed)
            : game.place(move.digit, at: move.cell, elapsed: elapsed)
        guard changed else { return nil }
        seats?.credit(seat: seat, firstMoveIndex: index, at: elapsed)
        if move.digit == 0 { return .erased }
        return .placed(wrong: game.isError(at: move.cell))
    }
}

extension DuelState {
    /// Credit the move logged at `index` to `seat`: a new turn only when the
    /// hand changes, so one person's run of digits is one turn.
    public mutating func credit(seat: Int, firstMoveIndex index: Int, at elapsed: TimeInterval) {
        guard turns.isEmpty || currentPlayer != seat else { return }
        beginTurn(player: seat, firstMoveIndex: index, startedAt: elapsed)
    }
}
