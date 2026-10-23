// VisionModel.swift — the whole of Nine's state on Vision Pro.
//
// Deliberately still not `AppModel`, for the watch's reason (WatchModel.swift):
// `AppModel` is the iPhone's, the TV's and the Mac's whole app, and Vision Pro
// plays one board in a room. What changed is that the headset now *joins* the
// other three instead of standing apart from them — play anywhere:
//
//   * the board lives in `nine.library`, the same `BoardLibrary` blob, synced
//     through the same `LibraryCloudStore` and merged by the same tested
//     `LibrarySync` rules. A board started on the phone opens here, and a
//     board finished here is solved there;
//   * a solve lands in `nine.history` (KVS) and on Game Center, so it counts
//     the same everywhere;
//   * the accent and theme are the ones the phone published.
//
// `LibraryCloudStore` builds a `CKContainer(identifier:)`, which traps on a
// binary without the CloudKit entitlement — the reason this target was
// local-only. It now carries `Nine-visionOS.entitlements`, and the store is
// compiled in on its own; `AppModel` still never reaches this target.
//
// Everything persisted decodes tolerantly (EXECUTING-A-PRD §2), and the one
// key of this target's own, `nine.vision.board`, gained only optional fields.
#if os(visionOS)
import Foundation
import Observation
import SwiftUI
import CouchKit
import GroupActivities

// `VisionSaveSlot` and the board rules live in `Sources/Shared/HeadsetBoards.swift`,
// where `swift test` holds them.

@MainActor
@Observable
final class VisionModel {
    @ObservationIgnored private let slotStore =
        CouchStored(wrappedValue: VisionSaveSlot(), "nine.vision.board")
    @ObservationIgnored private let libraryStore =
        CouchStored(wrappedValue: BoardLibrary(), "nine.library")
    @ObservationIgnored private let historyStore =
        CouchStored(wrappedValue: SolveHistory(), "nine.history", cloudSynced: true)
    /// The headset's own solves, minted here and kept until CloudKit has them:
    /// `LibraryCloudStore` holds a pushed replay only in memory, so a solve
    /// whose record had not gone out before the app was closed is re-sent from
    /// here on the next re-seed. Never read for display — there is no comet on
    /// this target — and never written from CloudKit (`onRemoteReplay` unset).
    /// Who placed which digit on a board solved together, keyed by board —
    /// PRD-27's `nine.duel` shape, a sibling blob rather than a field on
    /// `LibraryEntry` (EXECUTING-A-PRD §2). It is what keeps the tints, and the
    /// "nobody's solve" rule, true for a board after the call has ended or the
    /// app has been relaunched.
    @ObservationIgnored private let coSolveSeatsStore =
        CouchStored(wrappedValue: DuelLedger(), "nine.vision.cosolve")
    @ObservationIgnored private let replaysStore =
        CouchStored(wrappedValue: ReplayVault(), "nine.replays")
    @ObservationIgnored private var cloudStore: LibraryCloudStore?
    @ObservationIgnored private var kvsObserver: NSObjectProtocol?
    @ObservationIgnored private var composeGeneration = 0
    /// Whether the window is in the room yet. DEBUG staging waits on it: the
    /// first frame can come tens of seconds after `init` on a loaded simulator
    /// (RealityKit's scene setup), and a timer started in `init` runs out first.
    @ObservationIgnored private var sceneIsActive = false
    /// Whether the player has asked for Game Center on this headset. Until
    /// they have, `authenticate()` is never called: on visionOS GameKit
    /// answers it with a sign-in sheet of its own, in front of the board, and
    /// holding the view controller GameKit hands back does not stop it
    /// (observed on the visionOS 27 simulator). After the first pinch on the
    /// Game Center button, launches authenticate as every other platform does.
    @ObservationIgnored private let gameCenterOptIn =
        CouchStored(wrappedValue: false, "nine.vision.gameCenter")

    private var library: BoardLibrary {
        didSet { libraryStore.wrappedValue = library }
    }
    private(set) var entryID: UUID?
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
    /// A newer board another device moved, offered rather than opened while
    /// the one here is still in progress (`HeadsetBoards.afterMerge`). The
    /// bottom ornament shows it, so it is never seen on an idle board. Not
    /// persisted: the next merge or open decides it again.
    private(set) var offeredBoard: UUID?

    /// Published by the phone (`SharedAppearance`), read here, never written:
    /// a headset that wrote it would fight the phone under last-writer-wins,
    /// exactly as a wrist would.
    private(set) var appearance = SharedAppearance()
    var theme: ThemeChoice { ThemeChoice(rawValue: appearance.theme) ?? .auto }
    var accent: AccentChoice { AccentChoice(rawValue: appearance.accent) ?? .glacier }
    /// Whether the theme pins a light board. visionOS draws its glass dark, so
    /// only a theme that asks for light gets light tones.
    var isLight: Bool { theme.colorScheme == .light }

    let coSolve = VisionCoSolve()

    init() {
        library = libraryStore.wrappedValue
        let slot = slotStore.wrappedValue
        migrateLocalOnlySlot(slot)
        let remembered = entryID ?? slot.entryID
        if let entry = HeadsetBoards.atLaunch(library, remembered: remembered) {
            open(entry, cursor: entry.id == remembered ? slot.cursor : nil)
        } else {
            compose(.gentle)
        }
        coSolve.onRemoteMove = { [weak self] move in self?.applyRemote(move) }
        observeAppearance()
        if gameCenterOptIn.wrappedValue { GameCenter.shared.authenticate() }
        #if DEBUG
        stageForScreenshots()
        #endif
    }

    /// The first build's local-only board, moved into the library once so it
    /// syncs like any other (`HeadsetBoards.migrate`).
    private func migrateLocalOnlySlot(_ slot: VisionSaveSlot) {
        guard let moved = HeadsetBoards.migrate(slot, into: &library, now: Date()) else { return }
        entryID = moved.entryID
        slotStore.wrappedValue = moved
    }

    #if DEBUG
    /// Headless verification, the visionOS twin of `--debug-pad-gestures`: a
    /// simulator cannot be pinched from a script, so these stage the two
    /// states a screenshot has to see. `--vision-near-solve` fills every empty
    /// cell but one and selects it (the keypad is up); `--vision-solve` then
    /// places the last digit through `enter`, the same path a pinch takes.
    /// `--vision-coplay-demo` starts a co-solve with one ghost participant.
    /// `--vision-wait-go` holds staging further, until a file named
    /// `vision-go` appears in the app's tmp directory: a recorder that starts
    /// only once the window is up (recording slows a launch by minutes) drops
    /// the file to say "now".
    private func waitForScene(then seconds: Double) async {
        while !sceneIsActive { try? await Task.sleep(for: .milliseconds(250)) }
        if ProcessInfo.processInfo.arguments.contains("--vision-wait-go") { await waitForGo() }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func waitForGo() async {
        let go = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vision-go")
        while !FileManager.default.fileExists(atPath: go.path) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? FileManager.default.removeItem(at: go)
    }

    /// `--vision-theme <raw> [--vision-accent <raw>]`: the appearance a phone
    /// would have published, for a contrast pass. A simulator with no iCloud
    /// account never receives `SharedAppearance` from KVS, so without this
    /// every theme but the default is unreachable on one.
    @ObservationIgnored private var appearanceIsStaged = false

    private func stageForScreenshots() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        if let theme = value(after: "--vision-theme") {
            appearance = SharedAppearance(theme: theme, accent: value(after: "--vision-accent") ?? "")
            appearanceIsStaged = true
        }
        if args.contains("--vision-tour") {
            Task { @MainActor in await self.runTour() }
            return
        }
        if args.contains("--vision-offer-demo") {
            Task { @MainActor in
                await self.waitForScene(then: 2)
                self.stageOffer()
            }
        }
        if args.contains("--vision-chooser-demo") {
            Task { @MainActor in
                await self.waitForScene(then: 2)
                self.stageChooser()
            }
        }
        if args.contains("--vision-coplay-demo") {
            Task { @MainActor in
                await self.waitForScene(then: 2)
                self.startGhostCoSolve()
            }
        }
        guard args.contains("--vision-near-solve") || args.contains("--vision-solve"),
              var g = game else { return }
        let solution = g.puzzle.solution.cells
        let empty = (0..<81).filter { g.entry(at: $0) != solution[$0] }
        guard let last = empty.last else { return }
        for cell in empty.dropLast() { g.place(solution[cell], at: cell) }
        game = g
        solvedAt = nil
        cursor = last
        persist()
        if args.contains("--vision-solve") {
            Task { @MainActor in
                await self.waitForScene(then: 3)
                self.enter(solution[last])
            }
        }
    }

    /// `--vision-tour`: every board interaction in order, for a recording.
    /// No input can be injected into a visionOS simulator from a script (the
    /// simulator vends no HID digitizer), so this walks the same model calls a
    /// pinch on a cell or a key makes — `select`, `enter`, `erase`, `undo`,
    /// pencil mode, `compose` — with pauses long enough to watch each answer.
    /// It shows what the board does with a move; it does not show the gaze
    /// highlight, the pinch itself or the system menu, which only a person can.
    ///
    /// With `--vision-wait-go` every pause is instead a wait for the next
    /// `vision-go` file, so a capture script can photograph each state after
    /// the simulator has actually drawn it.
    private func runTour() async {
        let stepped = ProcessInfo.processInfo.arguments.contains("--vision-wait-go")
        func pause(_ seconds: Double) async {
            if stepped { await waitForGo() } else { try? await Task.sleep(for: .seconds(seconds)) }
        }
        func openCells() -> [Int] {
            guard let g = game else { return [] }
            return (0..<81).filter { g.entry(at: $0) == 0 && !g.isGiven($0) }
        }
        // A fresh board, resting: no cell selected, so no chrome at all.
        cursor = nil
        await waitForScene(then: 4)
        guard let g = game, openCells().count > 3 else { return }
        let solution = g.puzzle.solution.cells
        let cells = openCells()
        let (a, b, c) = (cells[0], cells[cells.count / 2], cells[cells.count - 1])

        select(a)                                   // the keypad and New Game arrive
        await pause(2.5)
        enter(solution[a])                          // a correct digit settles
        await pause(2.5)
        select(b)
        await pause(1.5)
        enter(solution[b] % 9 + 1)                  // a wrong digit shakes
        await pause(2.5)
        erase()                                     // and is erased
        await pause(2.5)
        enter(solution[b])
        await pause(2)
        undo()                                      // undo takes it back
        await pause(2.5)
        select(c)
        pencilMode = true                           // pencil mode: notes, not digits
        await pause(1.5)
        for note in [solution[c], solution[c] % 9 + 1, (solution[c] + 3) % 9 + 1] {
            enter(note)
            await pause(1)
        }
        pencilMode = false
        await pause(2)
        select(c)                                   // let go: the chrome recedes
        await pause(4)
        compose(.steady)                            // New Game, a band
        await pause(5)
        // Then a solve: everything but one cell, and the last digit by hand.
        guard var fresh = game else { return }
        let answer = fresh.puzzle.solution.cells
        let empty = (0..<81).filter { fresh.entry(at: $0) != answer[$0] }
        guard let last = empty.last else { return }
        for cell in empty.dropLast() { fresh.place(answer[cell], at: cell) }
        game = fresh
        persist()
        await pause(2)
        select(last)
        await pause(2.5)
        enter(answer[last])
    }

    /// `--vision-offer-demo`: the merge an iPhone's newer board would make,
    /// without an iCloud account — a Steady board a third filled lands in the
    /// library, the after-merge rule runs, and a cell is selected so the
    /// ornament carrying the offer is up.
    private func stageOffer() {
        var phone = NineGame(puzzle: PuzzleGenerator.generate(seed: 2026, difficulty: .steady))
        let answer = phone.puzzle.solution.cells
        for cell in (0..<81).filter({ !phone.isGiven($0) }).prefix(18) {
            phone.place(answer[cell], at: cell)
        }
        _ = library.create(kind: .free(.steady), game: phone, now: Date())
        refreshAfterMerge()
        if cursor == nil, let g = game { cursor = (0..<81).first { !g.isGiven($0) } }
    }

    /// `--vision-chooser-demo`: three boards in progress from other days, so
    /// the New Game menu has an "In progress" section to show, and a cell
    /// selected so the ornament carrying the menu is up. The menu itself
    /// opens only on a pinch.
    private func stageChooser() {
        let now = Date()
        for (seed, band, filled, age) in [(11, Difficulty.steady, 20, 2.0 * 3600),
                                          (12, .sharp, 9, 26 * 3600),
                                          (13, .gentle, 35, 3 * 86_400)] {
            var g = NineGame(puzzle: PuzzleGenerator.generate(seed: UInt64(seed), difficulty: band))
            let answer = g.puzzle.solution.cells
            for cell in (0..<81).filter({ !g.isGiven($0) }).prefix(filled) { g.place(answer[cell], at: cell) }
            _ = library.create(kind: .free(band), game: g, now: now - age)
        }
        if cursor == nil, let g = game { cursor = (0..<81).first { !g.isGiven($0) } }
    }

    private func startGhostCoSolve() {
        guard let game else { return }
        let ghost = VisionGhostTransport { [weak self] in
            guard let g = self?.game, !g.isSolved else { return nil }
            let solution = g.puzzle.solution.cells
            // Never the cell the player has selected: a ghost that typed into
            // your hands would be the one thing a demo must not show.
            let open = (0..<81).filter { g.entry(at: $0) == 0 && $0 != self?.cursor }
            return open.randomElement().map { ($0, solution[$0]) }
        }
        beginCoSolve(ParlorInvite(seed: game.puzzle.seed, difficulty: game.puzzle.difficulty),
                     over: ghost)
        ghost.start()
    }
    #endif

    var isSolved: Bool { solvedAt != nil }

    // MARK: - Boards

    private func open(_ entry: LibraryEntry, cursor: Int?) {
        var g = entry.game
        // A run still open at launch was left by a process that died, not by
        // an honest pause; nobody watched that gap, so it credits nothing. The
        // scene going active starts the clock again.
        if let since = g.timer.runningSince { g.timer.closeOpenRun(notLaterThan: since) }
        entryID = entry.id
        game = g
        // A daily (reachable from the chooser) has no band of its own; its
        // puzzle's is the one a solve on it records.
        if case .free(let band) = entry.kind { difficulty = band } else { difficulty = g.puzzle.difficulty }
        lastEvent = nil
        winningCell = nil
        pencilMode = false
        if g.isSolved || entry.status == .solved {
            // Reopening a solved board shows it solved, without replaying the
            // celebration as if it had just happened.
            solvedAt = .distantPast
            self.cursor = nil
        } else {
            solvedAt = nil
            self.cursor = cursor.flatMap { (0..<81).contains($0) ? $0 : nil }
        }
        saveSlot()
        reconsiderOffer()
    }

    /// "Continue your other board": open the offered board.
    func takeOffer() {
        guard let id = offeredBoard else { return }
        offeredBoard = nil
        switchBoard(to: id)
    }

    /// The New Game menu's "In progress" section (HEADSET-UX item 10).
    var chooserRows: [HeadsetBoards.ChooserRow] {
        HeadsetBoards.chooserRows(in: library, current: entryID)
    }

    /// A row of the chooser, or the offer: open another board in progress.
    func switchBoard(to id: UUID) {
        guard !coSolve.isActive, id != entryID, let entry = library.entry(id: id),
              entry.status == .inProgress, HeadsetBoards.isPlayable(entry.kind) else { return }
        pauseClock()
        open(entry, cursor: nil)
        resumeClockIfActive()
        // Pausing stamped the board left behind as the newest; starting the
        // clock here stamps this one. Decide again, or the ornament would
        // offer the way straight back.
        reconsiderOffer()
    }

    /// The board being left stops its clock where it is: a run left open would
    /// be closed at its start by the next `open`, and credit nothing.
    private func pauseClock() {
        guard var g = game, !isSolved else { return }
        g.timer.pause(at: Date())
        game = g
        persist()
    }

    /// `open` leaves the clock stopped; the scene going active starts it. A
    /// board opened while the window is already in the room starts it here.
    private func resumeClockIfActive() {
        guard sceneIsActive, var g = game, !isSolved else { return }
        g.timer.start(at: Date())
        game = g
        persist()
    }

    /// The offer, decided again from the library as it stands. Never during a
    /// co-solve: the board in a call is everybody's, and it does not move.
    private func reconsiderOffer() {
        guard !coSolve.isActive,
              case .offer(let id) = HeadsetBoards.afterMerge(in: library, current: entryID)
        else { return offeredBoard = nil }
        offeredBoard = id
    }

    func compose(_ band: Difficulty) {
        compose(band, seed: UInt64.random(in: .min ... .max))
    }

    /// `seed` is explicit for SharePlay: a joiner composes the invite's board,
    /// byte for byte, because generation is a pure function of the two.
    ///
    /// A SharePlay join (`then` set) may start while a board is composing; it
    /// wins, and the earlier one is dropped when it lands (`composeGeneration`).
    private func compose(_ band: Difficulty, seed: UInt64, then: (@MainActor () -> Void)? = nil) {
        guard !composing || then != nil else { return }
        composing = true
        composeGeneration += 1
        let generation = composeGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            // Pure, Sendable, deterministic — safe off the main actor.
            let puzzle = PuzzleGenerator.generate(seed: seed, difficulty: band)
            await MainActor.run {
                guard let self, generation == self.composeGeneration else { return }
                var fresh = NineGame(puzzle: puzzle)
                fresh.timer.start(at: Date())
                let id = self.library.create(kind: .free(band), game: fresh, now: Date())
                self.composing = false
                if let entry = self.library.entry(id: id) {
                    self.open(entry, cursor: nil)
                    self.cloudStore?.push(entry)
                }
                then?()
            }
        }
    }

    // MARK: - Selection

    /// Pinching the selected cell again lets go of it — and with it the chrome.
    func select(_ cell: Int) {
        guard !isSolved, (0..<81).contains(cell) else { return }
        cursor = cursor == cell ? nil : cell
        saveSlot()
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
        coSolve.attribute(seat: 0, firstMoveIndex: g.moveLog.count, elapsed: elapsed)
        guard g.place(digit, at: cell, elapsed: elapsed) else { return }
        game = g
        coSolve.send(cell: cell, digit: digit)
        let wrong = g.isError(at: cell)
        lastEvent = (cell, wrong ? .error : .place, Date())
        if g.isSolved {
            finishSolve(at: cell)
        } else {
            persist()
        }
    }

    func erase() {
        guard var g = game, let cell = cursor, !isSolved else { return }
        let elapsed = g.timer.elapsed(at: Date())
        coSolve.attribute(seat: 0, firstMoveIndex: g.moveLog.count, elapsed: elapsed)
        guard g.erase(at: cell, elapsed: elapsed) else { return }
        game = g
        coSolve.send(cell: cell, digit: 0)
        lastEvent = (cell, .erase, Date())
        persist()
    }

    func undo() {
        if coSolve.isActive { return undoOwnMove() }
        guard canUndo, var g = game,
              let move = g.undo(elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        cursor = move.cell
        persist()
    }

    /// In a co-solve the board's undo stack is everybody's, so undo walks
    /// back this headset's own moves instead (`CoSolveLedger.undoLast`) —
    /// never somebody else's digit.
    var canUndo: Bool {
        guard !isSolved else { return false }
        if coSolve.isActive { return coSolve.canUndo }
        return !(game?.undoStack.isEmpty ?? true)
    }

    /// Your last move in the call, taken back: the cell returns to what it
    /// held before, as a new move of yours everyone applies.
    private func undoOwnMove() {
        guard var g = game, !isSolved, let move = coSolve.takeBack(),
              let landing = coSolve.land(move, seat: 0, on: &g,
                                         elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        cursor = move.cell
        lastEvent = (move.cell, landing.event, Date())
        persist()
    }

    /// The keypad greys a digit once all nine are placed.
    func isDigitComplete(_ digit: Int) -> Bool { game?.isDigitComplete(digit) ?? false }

    // MARK: - Game Center

    /// The Game Center button: the dashboard once signed in, GameKit's held
    /// sign-in if it is waiting, and otherwise the first ask — which is the
    /// one moment a sign-in sheet in front of the board is what the player
    /// wanted.
    func gameCenterTapped() {
        let center = GameCenter.shared
        if center.isAuthenticated {
            center.showDashboard()
        } else if center.needsSignIn {
            center.signIn()
        } else {
            gameCenterOptIn.wrappedValue = true
            try? gameCenterOptIn.flushNow()
            center.authenticate(thenShowDashboard: true)
        }
    }

    // MARK: - SharePlay

    /// The invitation "Play together" shares: this board, as seed and band.
    var invitation: CoSolveInvitation? {
        guard let game, !isSolved else { return nil }
        return CoSolveInvitation(
            invite: ParlorInvite(seed: game.puzzle.seed, difficulty: game.puzzle.difficulty))
    }

    /// A session arrived (started here, or accepted from somebody else).
    func join(_ session: GroupSession<NineCoSolveActivity>) async {
        let transport = GroupCoSolveTransport(session: session)
        beginCoSolve(session.activity.invite, over: transport)
        await transport.join()
    }

    private func beginCoSolve(_ invite: ParlorInvite, over transport: any CoSolveTransport) {
        let sameBoard = game.map {
            $0.puzzle.seed == invite.seed && $0.puzzle.difficulty == invite.difficulty
        } ?? false
        offeredBoard = nil
        coSolve.begin(invite: invite, fillable: fillable, accent: accent.rawValue,
                      resuming: sameBoard ? savedSeats : nil, over: transport)
        if sameBoard, !isSolved {
            coSolveReady()
        } else {
            compose(invite.difficulty, seed: invite.seed) { [weak self] in self?.coSolveReady() }
        }
    }

    /// "Leave": out of the call, keeping the board as it stands — digits,
    /// tints and all. The system's own SharePlay control ends it the same way.
    func leaveCoSolve() {
        saveSeats()
        coSolve.end()
        reconsiderOffer()
    }

    private func coSolveReady() {
        guard let game else { return }
        var own: [Int: Int] = [:]
        for cell in 0..<81 where !game.isGiven(cell) && game.entry(at: cell) != 0 {
            own[cell] = game.entry(at: cell)
        }
        coSolve.ready(ownEntries: own)
        reportCoSolve()
    }

    /// Somebody else's digit. It lands through the same `place`/`erase` the
    /// keypad uses, so the move log, the settle and the shake are the board's
    /// own — and is credited to seat 1, which is what tints it.
    private func applyRemote(_ move: CoSolveMove) {
        guard var g = game, !isSolved else { return }
        guard let landing = coSolve.land(move, seat: 1, on: &g,
                                         elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        lastEvent = (move.cell, landing.event, Date())
        if g.isSolved {
            finishSolve(at: move.cell)
        } else {
            persist()
        }
    }

    /// The per-cell tint while a co-solve is on: yours in your accent, every
    /// other hand in `DuelTint`'s partner. Nil outside one, so the board draws
    /// exactly as it always has.
    var digitTint: ((Int) -> Color?)? {
        let live = coSolve.isShared ? coSolve.seats : nil
        guard let seats = live ?? savedSeats, let game,
              seats.turns.contains(where: { $0.player != 0 }),
              // A log that no longer reaches the last turn was replaced (a
              // merge from another device); its indices would tint the wrong
              // cells, so it tints none.
              (seats.turns.last?.firstMoveIndex ?? 0) <= game.moveLog.count
        else { return nil }
        let owners = DuelCredits.owners(state: seats, moves: game.moveLog)
        let isLight = isLight
        return { cell in
            owners[cell].map {
                (AccentChoice(rawValue: seats.accent(forPlayer: $0)) ?? .glacier)
                    .color(isLight: isLight)
            }
        }
    }

    private var fillable: Int {
        guard let game else { return 0 }
        return (0..<81).filter { !game.isGiven($0) }.count
    }

    private func reportCoSolve() {
        guard coSolve.isActive, let game else { return }
        let filled = (0..<81).filter { !game.isGiven($0) && game.entry(at: $0) != 0 }.count
        coSolve.report(fill: filled, done: game.isSolved, fillable: fillable)
    }

    // MARK: - Lifecycle

    /// The timer runs only while the window is in the room; coming forward is
    /// also when the library catches up with the other devices.
    func scene(active: Bool) {
        sceneIsActive = active
        if active { syncOnForeground() }
        guard var g = game, !isSolved else { return }
        if active { g.timer.start(at: Date()) } else { g.timer.pause(at: Date()) }
        game = g
        persist()
        if !active {
            try? libraryStore.flushNow()
            try? slotStore.flushNow()
        }
    }

    private func finishSolve(at cell: Int) {
        guard var g = game, let id = entryID else { return }
        let now = Date()
        g.timer.pause(at: now)
        game = g
        winningCell = cell
        solvedAt = now
        cursor = nil
        pencilMode = false
        persist()
        library.markSolved(id: id, at: now)
        if let solved = library.entry(id: id) { cloudStore?.push(solved) }
        try? libraryStore.flushNow()
        mintReplay(boardID: id, game: g, at: now)
        reportCoSolve()
        // A board somebody else also filled in is nobody's solve (PRD-27 §7) —
        // during the call, or after it, from the attribution it left behind.
        let shared = coSolve.isShared
            || (savedSeats?.turns.contains { $0.player != 0 } ?? false)
        saveSeats()
        guard !shared else { return }
        recordSolve(game: g, at: now)
    }

    /// One classic solve, into the history every device reads and onto Game
    /// Center — the same `SolveRecord` the phone writes for a free board.
    ///
    /// `nine.history` is one KVS blob under last-writer-wins, and this headset
    /// may hold a stale copy of it. So the write starts from the newest copy
    /// KVS has and folds this headset's in (`SolveHistory.merged`): writing
    /// back cannot drop a solve the phone recorded since the headset last
    /// looked. Every other writer does the same since (`AppModel`).
    private func recordSolve(game g: NineGame, at now: Date) {
        let seconds = g.timer.elapsed(at: now)
        let record = SolveRecord(
            date: now, difficulty: difficulty, isDaily: false, seconds: seconds,
            points: SolveScore.points(difficulty: difficulty, isDaily: false,
                                      streak: 0, seconds: seconds),
            errors: g.errorCount)
        var history = historyStore.wrappedValue.mergedWithShared(
            NSUbiquitousKeyValueStore.default.data(
                forKey: CouchKeyspace.namespacedKey("nine.history")))
        history.record(record)
        historyStore.wrappedValue = history
        try? historyStore.flushNow()
        GameCenter.shared.reportSolve(record: record, history: history)
    }

    /// The board's replay, for the phone's comet and debrief. A replay is the
    /// board's, not a player's, so a co-solve mints one too — `AppModel`'s
    /// duel rule (the history and Game Center stay nobody's). Pure Engine
    /// minting (`SolveReplay(boardID:game:…)`), nil for a board with no log,
    /// and pushed through the same store the board went through.
    private func mintReplay(boardID: UUID, game g: NineGame, at now: Date) {
        guard let replay = SolveReplay(
            boardID: boardID, game: g, band: difficulty.rawValue,
            isDaily: false, solvedAt: now, seconds: g.timer.elapsed(at: now)) else { return }
        var vault = replaysStore.wrappedValue
        vault.store(replay)
        vault.prune(to: Set(library.entries.map { $0.id.uuidString }))
        replaysStore.wrappedValue = vault
        try? replaysStore.flushNow()
        cloudStore?.push(replay)
    }

    private func persist() {
        if let game, let id = entryID, var entry = library.entry(id: id) {
            entry.game = game
            entry.updatedAt = Date()
            library.upsert(entry)
            cloudStore?.push(entry)
        }
        saveSlot()
        saveSeats()
        reportCoSolve()
    }

    /// The attribution of the board on the headset, from an earlier call.
    private var savedSeats: DuelState? {
        entryID.flatMap { coSolveSeatsStore.wrappedValue[$0] }
    }

    /// Keep the live call's attribution against this board once somebody
    /// else's digit is on it. Pruned to the library, like `nine.duel`.
    private func saveSeats() {
        guard coSolve.isShared, let seats = coSolve.seats, let id = entryID else { return }
        var ledger = coSolveSeatsStore.wrappedValue
        guard ledger[id] != seats else { return }
        ledger.set(seats, for: id)
        ledger.prune(to: Set(library.entries.map(\.id)))
        coSolveSeatsStore.wrappedValue = ledger
    }

    private func saveSlot() {
        var slot = VisionSaveSlot()
        slot.entryID = entryID
        slot.cursor = cursor
        slotStore.wrappedValue = slot
    }

    // MARK: - Appearance (KVS)

    private func observeAppearance() {
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()
        readAppearance()
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.readAppearance() }
        }
    }

    /// Straight from KVS rather than through a `CouchStored`: that wrapper
    /// prefers its local file and reads KVS only on a fresh install, and this
    /// value is never written here, so the live KVS copy is the only truth.
    private func readAppearance() {
        #if DEBUG
        if appearanceIsStaged { return }
        #endif
        let key = CouchKeyspace.namespacedKey(SharedAppearance.storeKey)
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key),
              let published = try? CouchJSON.decode(SharedAppearance.self, from: data),
              published != appearance else { return }
        appearance = published
    }

    // MARK: - Cloud sync (PRD-8, reused whole)

    private func syncOnForeground() {
        setUpCloudSyncIfAvailable()
        cloudStore?.kick()
    }

    /// Only with an iCloud account signed in **and** a binary entitled to
    /// CloudKit — the same two gates `AppModel` uses. The second is what keeps
    /// an unsigned simulator build (`CODE_SIGNING_ALLOWED=NO`, no entitlements
    /// at all) from trapping in `CKContainer.init` once an account is signed in.
    private func setUpCloudSyncIfAvailable() {
        guard cloudStore == nil, CloudEntitlement.thisProcessGrantsCloudKit,
              FileManager.default.ubiquityIdentityToken != nil else { return }
        let store = LibraryCloudStore()
        store.onRemoteEntry = { [weak self] synced in self?.applyRemoteEntry(synced) }
        store.onRemoteDeletion = { [weak self] id in self?.applyRemoteDeletion(id) }
        store.onAccountReset = { [weak self] in self?.repushEntireLibrary() }
        // Replays minted here go up; none come down. There is no comet to
        // draw one with, so `onRemoteReplay` stays unset and an incoming
        // replay record is simply skipped.
        cloudStore = store
        store.start()
        if !store.hasSyncedBefore { repushEntireLibrary() }
    }

    private func repushEntireLibrary() {
        for entry in library.entries { cloudStore?.push(entry) }
        for replay in replaysStore.wrappedValue.all { cloudStore?.push(replay) }
    }

    private func applyRemoteEntry(_ synced: SyncedEntry) {
        let effects = LibrarySync.apply(
            remote: synced, into: &library, now: Date(), makeID: { UUID() })
        try? libraryStore.flushNow()
        for id in effects.reupload {
            if let entry = library.entry(id: id) { cloudStore?.push(entry) }
        }
        for id in effects.cloudDeletes { cloudStore?.delete(id) }
        refreshAfterMerge()
    }

    private func applyRemoteDeletion(_ id: UUID) {
        LibrarySync.applyDeletion(id: id, into: &library)
        try? libraryStore.flushNow()
        var vault = replaysStore.wrappedValue
        vault.remove(id)
        replaysStore.wrappedValue = vault
        if entryID == id { entryID = nil }
        if offeredBoard == id { reconsiderOffer() }
    }

    /// After a merge: if this board moved elsewhere, show where it is now.
    /// If another device has since moved a newer board, offer it — or, when
    /// the board here is solved or gone and there is nothing to keep, open it
    /// (`HeadsetBoards.afterMerge`). The silent switch this replaces changed
    /// the board under a player who was only looking at it (HEADSET-UX item 9).
    private func refreshAfterMerge() {
        guard !coSolve.isActive else { return }
        if let id = entryID, let merged = library.entry(id: id),
           let game, merged.game.entries != game.entries || merged.status == .solved {
            let wasSolved = isSolved
            open(merged, cursor: cursor)
            if !wasSolved, isSolved { winningCell = nil }
        }
        switch HeadsetBoards.afterMerge(in: library, current: entryID) {
        case .stay: offeredBoard = nil
        case .offer(let id): offeredBoard = id
        case .open(let id):
            guard let entry = library.entry(id: id) else { return }
            open(entry, cursor: nil)
            resumeClockIfActive()
        }
    }
}

extension CoSolveLanding {
    /// The board's answer to draw for it.
    var event: CellEventKind {
        switch self {
        case .placed(let wrong): return wrong ? .error : .place
        case .erased: return .erase
        }
    }
}
#endif
