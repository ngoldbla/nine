// HeadsetBoardsTests — which board Vision Pro opens, as pure rules.
//
// The headset draws classic boards only: it has no `channelRules` (they are
// local to the device that composed the board, and do not sync), so a Thermo or
// Killer board would draw as a plain sudoku with its cages and thermometers
// missing. `mostRecentFreePartial` happened to keep it on classic; these pin
// that as a rule for every way a board reaches the headset.
import Testing
import Foundation
@testable import NineShared
import NineEngine

@Suite("HeadsetBoards")
struct HeadsetBoardsTests {

    private static let game = NineGame(puzzle: PuzzleGenerator.generate(seed: 42, difficulty: .gentle))
    private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + s) }

    @Test func onlyClassicKindsArePlayable() {
        #expect(HeadsetBoards.isPlayable(.free(.steady)))
        #expect(HeadsetBoards.isPlayable(.daily(day: 20_600)))
        #expect(!HeadsetBoards.isPlayable(.channel(channel: .thermo, tier: .steady, day: nil)))
        #expect(!HeadsetBoards.isPlayable(.channel(channel: .killer, tier: .steady, day: 20_600)))
    }

    @Test func aRememberedChannelBoardIsNotReopened() {
        var library = BoardLibrary()
        let free = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let thermo = library.create(kind: .channel(channel: .thermo, tier: .steady, day: nil),
                                    game: Self.game, now: at(10))
        #expect(HeadsetBoards.atLaunch(library, remembered: thermo)?.id == free)
        #expect(HeadsetBoards.atLaunch(library, remembered: free)?.id == free)
    }

    @Test func aRememberedSolvedBoardStillReopensSolved() {
        var library = BoardLibrary()
        let id = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        library.markSolved(id: id, at: at(5))
        #expect(HeadsetBoards.atLaunch(library, remembered: id)?.id == id)
    }

    @Test func nothingToReopenMeansComposeAFreshOne() {
        var library = BoardLibrary()
        library.create(kind: .channel(channel: .killer, tier: .gentle, day: nil), game: Self.game, now: at(0))
        #expect(HeadsetBoards.atLaunch(library, remembered: nil) == nil)
    }

    @Test func aNewerChannelBoardFromThePhoneIsNeverOffered() {
        var library = BoardLibrary()
        let mine = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        library.create(kind: .channel(channel: .thermo, tier: .steady, day: nil), game: Self.game, now: at(50))
        #expect(HeadsetBoards.newerBoard(in: library, current: mine) == nil)
    }

    @Test func thePhonesNewerFreeBoardIsOfferedOverAnOlderOne() {
        var library = BoardLibrary()
        let mine = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let phone = library.create(kind: .free(.steady), game: Self.game, now: at(50))
        #expect(HeadsetBoards.newerBoard(in: library, current: mine)?.id == phone)
        #expect(HeadsetBoards.newerBoard(in: library, current: phone) == nil)
    }

    @Test func aSolvedOrMissingBoardGivesWayToAnyPartial() {
        var library = BoardLibrary()
        let partial = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let done = library.create(kind: .free(.gentle), game: Self.game, now: at(10))
        library.markSolved(id: done, at: at(20))
        #expect(HeadsetBoards.newerBoard(in: library, current: done)?.id == partial)
        #expect(HeadsetBoards.newerBoard(in: library, current: UUID())?.id == partial)
        #expect(HeadsetBoards.newerBoard(in: library, current: nil)?.id == partial)
    }

    // MARK: After a merge — offer, switch, or stay (HEADSET-UX item 9)

    @Test func aNewerBoardIsOfferedWhileTheCurrentOneIsInProgress() {
        var library = BoardLibrary()
        let mine = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let phone = library.create(kind: .free(.steady), game: Self.game, now: at(50))
        #expect(HeadsetBoards.afterMerge(in: library, current: mine) == .offer(phone))
    }

    @Test func aSolvedOrMissingCurrentBoardSwitchesSilently() {
        var library = BoardLibrary()
        let partial = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let done = library.create(kind: .free(.gentle), game: Self.game, now: at(10))
        library.markSolved(id: done, at: at(20))
        #expect(HeadsetBoards.afterMerge(in: library, current: done) == .open(partial))
        #expect(HeadsetBoards.afterMerge(in: library, current: UUID()) == .open(partial))
        #expect(HeadsetBoards.afterMerge(in: library, current: nil) == .open(partial))
    }

    @Test func nothingNewerMeansStay() {
        var library = BoardLibrary()
        let older = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let mine = library.create(kind: .free(.steady), game: Self.game, now: at(50))
        #expect(HeadsetBoards.afterMerge(in: library, current: mine) == .stay)
        // The offer re-evaluates on every merge: once the headset's board is
        // the newer one again, an offer of the older board is withdrawn.
        #expect(HeadsetBoards.afterMerge(in: library, current: older) == .offer(mine))
    }

    @Test func anOfferIsWithdrawnWhenTheCandidateIsSolvedOrRemoved() {
        var library = BoardLibrary()
        let mine = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let phone = library.create(kind: .free(.steady), game: Self.game, now: at(50))
        #expect(HeadsetBoards.afterMerge(in: library, current: mine) == .offer(phone))
        var solved = library
        solved.markSolved(id: phone, at: at(60))
        #expect(HeadsetBoards.afterMerge(in: solved, current: mine) == .stay)
        var removed = library
        removed.delete(id: phone)
        #expect(HeadsetBoards.afterMerge(in: removed, current: mine) == .stay)
    }

    @Test func aChannelBoardIsNeverOfferedOrSwitchedTo() {
        var library = BoardLibrary()
        let done = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        library.markSolved(id: done, at: at(5))
        library.create(kind: .channel(channel: .thermo, tier: .steady, day: nil), game: Self.game, now: at(50))
        #expect(HeadsetBoards.afterMerge(in: library, current: done) == .stay)
    }

    // MARK: The board chooser — "In progress" in the New Game menu (item 10)

    @Test func theChooserListsClassicPartialsNewestFirstWithoutTheCurrentOne() {
        var library = BoardLibrary()
        let old = library.create(kind: .free(.gentle), game: Self.game, now: at(0))
        let daily = library.create(kind: .daily(day: 20_600), game: Self.game, now: at(10))
        library.create(kind: .channel(channel: .killer, tier: .steady, day: nil), game: Self.game, now: at(20))
        let done = library.create(kind: .free(.sharp), game: Self.game, now: at(30))
        library.markSolved(id: done, at: at(35))
        let mine = library.create(kind: .free(.steady), game: Self.game, now: at(40))
        let rows = HeadsetBoards.chooserRows(in: library, current: mine)
        #expect(rows.map(\.id) == [daily, old])
    }

    @Test func theChooserStopsAtFive() {
        var library = BoardLibrary()
        let ids = (0..<8).map { library.create(kind: .free(.gentle), game: Self.game, now: at(Double($0))) }
        let rows = HeadsetBoards.chooserRows(in: library, current: nil)
        #expect(rows.map(\.id) == Array(ids.reversed().prefix(5)))
    }

    @Test func aRowCarriesItsBandCellsLeftAndWhen() throws {
        var played = Self.game
        let open = (0..<81).filter { !played.isGiven($0) }
        _ = played.place(played.puzzle.solution.cells[open[0]], at: open[0])
        // A wrong digit still fills the square: "left" counts empty squares.
        _ = played.place(played.puzzle.solution.cells[open[1]] % 9 + 1, at: open[1])
        var library = BoardLibrary()
        let free = library.create(kind: .free(.steady), game: played, now: at(5))
        let daily = library.create(kind: .daily(day: 20_600), game: Self.game, now: at(9))
        let rows = HeadsetBoards.chooserRows(in: library, current: nil)
        let freeRow = try #require(rows.first { $0.id == free })
        #expect(freeRow.band == .steady)
        #expect(freeRow.cellsLeft == open.count - 2)
        #expect(freeRow.updatedAt == at(5))
        // A board with no band of its own (a daily) shows its puzzle's.
        let dailyRow = try #require(rows.first { $0.id == daily })
        #expect(dailyRow.band == Self.game.puzzle.difficulty)
        #expect(dailyRow.cellsLeft == open.count)
    }

    @Test func anEmptyLibraryHasNoRows() {
        #expect(HeadsetBoards.chooserRows(in: BoardLibrary(), current: nil).isEmpty)
    }
}

/// The first Vision build saved one board, locally, in `nine.vision.board`.
@Suite("HeadsetBoards slot migration")
struct HeadsetSlotMigrationTests {
    private static let game = NineGame(puzzle: PuzzleGenerator.generate(seed: 9, difficulty: .steady))

    @Test func aLocalOnlyBoardMovesIntoTheLibraryOnce() throws {
        var slot = VisionSaveSlot()
        slot.game = Self.game
        slot.difficulty = .steady
        slot.cursor = 40
        var library = BoardLibrary()
        let moved = try #require(HeadsetBoards.migrate(slot, into: &library, now: Date()))
        let movedID = try #require(moved.entryID)
        let entry = try #require(library.entry(id: movedID))
        #expect(entry.kind == .free(.steady))
        #expect(entry.status == .inProgress)
        #expect(moved.cursor == 40)
        #expect(moved.game == nil && moved.difficulty == nil, "the old fields are never written again")
        #expect(HeadsetBoards.migrate(moved, into: &library, now: Date()) == nil)
    }

    @Test func aSolvedLocalBoardArrivesSolvedAndABandlessOneAsGentle() throws {
        var solved = Self.game
        let answer = solved.puzzle.solution.cells
        for cell in 0..<81 where !solved.isGiven(cell) { _ = solved.place(answer[cell], at: cell) }
        var slot = VisionSaveSlot()
        slot.game = solved
        var library = BoardLibrary()
        let moved = try #require(HeadsetBoards.migrate(slot, into: &library, now: Date()))
        let movedID = try #require(moved.entryID)
        let entry = try #require(library.entry(id: movedID))
        #expect(entry.status == .solved)
        #expect(entry.kind == .free(.gentle))
    }

    @Test func aSlotWithNothingToMoveIsLeftAlone() {
        var library = BoardLibrary()
        #expect(HeadsetBoards.migrate(VisionSaveSlot(), into: &library, now: Date()) == nil)
        #expect(library.entries.isEmpty)
    }
}
