// CoSolveTests.swift — the Vision Pro co-solve's convergence rule.
//
// The point of `CoSolveLedger` is that two headsets which saw the same moves in
// different orders hold the same board. A FaceTime call between two simulators
// cannot be placed, so that claim is checked here or nowhere.
import XCTest
@testable import NineShared
import NineEngine

final class CoSolveTests: XCTestCase {

    private let ana = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let ben = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func board(_ ledger: CoSolveLedger) -> [Int: Int] {
        ledger.cells.mapValues(\.digit)
    }

    func testALocalMoveWinsAndAdvancesTheClock() {
        var ledger = CoSolveLedger()
        let first = ledger.stamp(cell: 4, digit: 7, author: ana)
        let second = ledger.stamp(cell: 4, digit: 3, author: ana)
        XCTAssertLessThan(first.clock, second.clock)
        XCTAssertEqual(board(ledger), [4: 3])
    }

    func testARemoteMoveCarriesTheClockForward() {
        var ledger = CoSolveLedger()
        XCTAssertTrue(ledger.apply(CoSolveMove(cell: 0, digit: 1, clock: 41, author: ben)))
        XCTAssertEqual(ledger.stamp(cell: 1, digit: 2, author: ana).clock, 42)
    }

    /// The headline: two concurrent writes to one cell, delivered in opposite
    /// orders on two headsets, leave both holding the same digit.
    func testConcurrentWritesConvergeWhateverTheArrivalOrder() {
        var anaLedger = CoSolveLedger()
        var benLedger = CoSolveLedger()
        let fromAna = anaLedger.stamp(cell: 10, digit: 5, author: ana)
        let fromBen = benLedger.stamp(cell: 10, digit: 8, author: ben)
        XCTAssertEqual(fromAna.clock, fromBen.clock, "the case that needs the tie-break")
        _ = anaLedger.apply(fromBen)
        _ = benLedger.apply(fromAna)
        XCTAssertEqual(board(anaLedger), board(benLedger))
    }

    func testAStaleMoveIsRefusedAndReportedAsNoChange() {
        var ledger = CoSolveLedger()
        _ = ledger.apply(CoSolveMove(cell: 3, digit: 9, clock: 5, author: ben))
        XCTAssertFalse(ledger.apply(CoSolveMove(cell: 3, digit: 2, clock: 4, author: ben)))
        XCTAssertEqual(board(ledger), [3: 9])
    }

    func testAnEraseIsAMoveLikeAnyOther() {
        var ledger = CoSolveLedger()
        _ = ledger.stamp(cell: 7, digit: 4, author: ana)
        XCTAssertTrue(ledger.apply(CoSolveMove(cell: 7, digit: 0, clock: 9, author: ben)))
        XCTAssertEqual(board(ledger), [7: 0])
    }

    func testAMalformedMoveTouchesNothing() {
        var ledger = CoSolveLedger()
        for bad in [CoSolveMove(cell: 81, digit: 1, clock: 1, author: ben),
                    CoSolveMove(cell: -1, digit: 1, clock: 1, author: ben),
                    CoSolveMove(cell: 0, digit: 10, clock: 1, author: ben),
                    CoSolveMove(cell: 0, digit: 1, clock: 0, author: ben)] {
            XCTAssertFalse(ledger.apply(bad))
        }
        XCTAssertTrue(ledger.cells.isEmpty)
        XCTAssertEqual(ledger.clock, 0, "a rejected move must not drag the clock")
    }

    /// A late joiner who replays the snapshot holds the board the room holds.
    func testASnapshotReplaysToTheSameBoard() throws {
        var room = CoSolveLedger()
        _ = room.stamp(cell: 1, digit: 1, author: ana)
        _ = room.apply(CoSolveMove(cell: 2, digit: 2, clock: 7, author: ben))
        _ = room.stamp(cell: 1, digit: 6, author: ana)
        let wire = try JSONDecoder().decode(
            CoSolveSnapshot.self, from: JSONEncoder().encode(room.snapshot))
        var joiner = CoSolveLedger()
        for move in wire.moves { _ = joiner.apply(move) }
        XCTAssertEqual(board(joiner), board(room))
        XCTAssertEqual(joiner.clock, room.clock)
    }

    func testAnUnreadableSnapshotIsEmptyRatherThanAThrow() throws {
        let decoded = try JSONDecoder().decode(
            CoSolveSnapshot.self, from: Data(#"{"moves": "not a list"}"#.utf8))
        XCTAssertTrue(decoded.moves.isEmpty)
    }

    // MARK: - Undo, your own moves only

    /// Undo in a co-solve takes back *your* last move and nobody else's: it
    /// restores what the cell held before it, as a new move everyone applies.
    func testUndoTakesBackYourLastMoveAsANewMove() throws {
        var ledger = CoSolveLedger()
        _ = ledger.stamp(cell: 3, digit: 4, author: ana)
        _ = ledger.stamp(cell: 7, digit: 9, author: ana)
        XCTAssertTrue(ledger.apply(CoSolveMove(cell: 12, digit: 1, clock: 9, author: ben)))
        let undo = try XCTUnwrap(ledger.undoLast(author: ana))
        XCTAssertEqual(undo.cell, 7)
        XCTAssertEqual(undo.digit, 0, "the cell was empty before your 9")
        XCTAssertGreaterThan(undo.clock, 9, "an undo is a new move, past everything seen")
        XCTAssertEqual(board(ledger), [3: 4, 7: 0, 12: 1], "ben's 1 is untouched")
    }

    func testUndoRestoresWhateverYourMoveReplaced() throws {
        var ledger = CoSolveLedger()
        XCTAssertTrue(ledger.apply(CoSolveMove(cell: 5, digit: 2, clock: 1, author: ben)))
        _ = ledger.stamp(cell: 5, digit: 6, author: ana)
        XCTAssertEqual(try XCTUnwrap(ledger.undoLast(author: ana)).digit, 2)
    }

    /// A move somebody has since written over is not yours to take back any
    /// more; undo skips it and reaches for the one before.
    func testUndoSkipsAMoveSomebodyElseHasOverwritten() throws {
        var ledger = CoSolveLedger()
        _ = ledger.stamp(cell: 1, digit: 1, author: ana)
        let mine = ledger.stamp(cell: 2, digit: 2, author: ana)
        XCTAssertTrue(ledger.apply(CoSolveMove(cell: 2, digit: 8, clock: mine.clock + 1, author: ben)))
        let undo = try XCTUnwrap(ledger.undoLast(author: ana))
        XCTAssertEqual(undo.cell, 1)
        XCTAssertEqual(board(ledger)[2], 8)
        XCTAssertNil(ledger.undoLast(author: ana), "nothing left of ana's to take back")
    }

    /// The board this headset brought into the call is not undoable: it was
    /// stamped so a late joiner gets it, not placed in the call.
    func testTheBoardYouArrivedWithIsNotUndoable() {
        var ledger = CoSolveLedger()
        _ = ledger.stamp(cell: 0, digit: 5, author: ana, undoable: false)
        XCTAssertFalse(ledger.canUndo(author: ana))
        XCTAssertNil(ledger.undoLast(author: ana))
    }

    /// Undoing an undo is not redo; it is a move like any other, and the
    /// stack does not grow from it.
    func testAnUndoIsNotItselfUndone() throws {
        var ledger = CoSolveLedger()
        _ = ledger.stamp(cell: 4, digit: 4, author: ana)
        _ = try XCTUnwrap(ledger.undoLast(author: ana))
        XCTAssertFalse(ledger.canUndo(author: ana))
    }

    // MARK: - Landing a move on the board (lifted out of VisionModel)

    private func fresh() -> NineGame {
        NineGame(puzzle: PuzzleGenerator.generate(seed: 7, difficulty: .gentle))
    }

    private func openCell(_ g: NineGame) -> Int { (0..<81).first { !g.isGiven($0) }! }

    func testARemoteDigitLandsAndIsCreditedToItsSeat() throws {
        var game = fresh()
        var seats: DuelState? = DuelState(accent: "glacier", isLight: false, turnLength: .standard)
        let cell = openCell(game)
        let digit = game.puzzle.solution.cells[cell]
        let landing = CoSolveBoard.land(CoSolveMove(cell: cell, digit: digit, clock: 1, author: ben),
                                        seat: 1, on: &game, seats: &seats, elapsed: 5)
        XCTAssertEqual(landing, .placed(wrong: false))
        XCTAssertEqual(game.entry(at: cell), digit)
        let owners = DuelCredits.owners(state: try XCTUnwrap(seats), moves: game.moveLog)
        XCTAssertEqual(owners[cell], 1)
    }

    func testAWrongDigitAndAnEraseLandAsTheBoardAnswersThem() {
        var game = fresh()
        var seats: DuelState?
        let cell = openCell(game)
        let wrong = game.puzzle.solution.cells[cell] % 9 + 1
        XCTAssertEqual(CoSolveBoard.land(CoSolveMove(cell: cell, digit: wrong, clock: 1, author: ben),
                                         seat: 1, on: &game, seats: &seats, elapsed: 0),
                       .placed(wrong: true))
        XCTAssertEqual(CoSolveBoard.land(CoSolveMove(cell: cell, digit: 0, clock: 2, author: ben),
                                         seat: 1, on: &game, seats: &seats, elapsed: 0),
                       .erased)
    }

    /// A move that changes nothing — onto a given, or the digit already
    /// there — lands nowhere and opens no turn, so it tints nothing.
    func testAMoveThatChangesNothingOpensNoTurn() {
        var game = fresh()
        var seats: DuelState? = DuelState(accent: "glacier", isLight: false, turnLength: .standard)
        let given = (0..<81).first { game.isGiven($0) }!
        XCTAssertNil(CoSolveBoard.land(CoSolveMove(cell: given, digit: 1, clock: 1, author: ben),
                                       seat: 1, on: &game, seats: &seats, elapsed: 0))
        XCTAssertEqual(seats?.turns.count, 0)
    }

    func testOneHandsRunOfMovesIsOneTurn() {
        var game = fresh()
        var seats: DuelState? = DuelState(accent: "glacier", isLight: false, turnLength: .standard)
        let open = (0..<81).filter { !game.isGiven($0) }
        for (n, cell) in open.prefix(3).enumerated() {
            _ = CoSolveBoard.land(CoSolveMove(cell: cell, digit: game.puzzle.solution.cells[cell],
                                              clock: n + 1, author: ben),
                                  seat: 1, on: &game, seats: &seats, elapsed: 0)
        }
        _ = CoSolveBoard.land(CoSolveMove(cell: open[3], digit: game.puzzle.solution.cells[open[3]],
                                          clock: 9, author: ana),
                              seat: 0, on: &game, seats: &seats, elapsed: 0)
        XCTAssertEqual(seats?.turns.map(\.player), [1, 0])
    }
}
