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
}
