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

    public init() {}

    /// A move made on this headset. Always wins locally — it is stamped past
    /// everything this participant has seen.
    public mutating func stamp(cell: Int, digit: Int, author: UUID) -> CoSolveMove {
        clock += 1
        let move = CoSolveMove(cell: cell, digit: digit, clock: clock, author: author)
        cells[cell] = move
        return move
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
