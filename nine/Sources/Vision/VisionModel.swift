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

/// Where the player left off on this headset: which library board, and the
/// cursor on it. The board itself is in `nine.library`.
///
/// `game` and `difficulty` are the pre-sync slot's fields, read once to move a
/// board saved by the first, local-only build into the library, and never
/// written again.
struct VisionSaveSlot: Codable, Sendable, Equatable {
    var entryID: UUID?
    var cursor: Int?
    var game: NineGame?
    var difficulty: Difficulty?

    init() {}

    enum CodingKeys: String, CodingKey { case entryID, cursor, game, difficulty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryID = (try? c.decodeIfPresent(UUID.self, forKey: .entryID)) ?? nil
        cursor = (try? c.decodeIfPresent(Int.self, forKey: .cursor)) ?? nil
        game = (try? c.decodeIfPresent(NineGame.self, forKey: .game)) ?? nil
        // `try?` because a future band this build cannot name must not throw
        // the board away with it.
        difficulty = (try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? nil
    }
}

@MainActor
@Observable
final class VisionModel {
    @ObservationIgnored private let slotStore =
        CouchStored(wrappedValue: VisionSaveSlot(), "nine.vision.board")
    @ObservationIgnored private let libraryStore =
        CouchStored(wrappedValue: BoardLibrary(), "nine.library")
    @ObservationIgnored private let historyStore =
        CouchStored(wrappedValue: SolveHistory(), "nine.history", cloudSynced: true)
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
        if let id = entryID ?? slot.entryID, let entry = library.entry(id: id) {
            open(entry, cursor: slot.cursor)
        } else if let partial = library.mostRecentFreePartial {
            open(partial, cursor: nil)
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

    /// The first build saved one board, locally, in the slot. Move it into the
    /// library once so it syncs like any other, then forget the old fields.
    private func migrateLocalOnlySlot(_ slot: VisionSaveSlot) {
        guard slot.entryID == nil, let old = slot.game else { return }
        let now = Date()
        let id = library.create(kind: .free(slot.difficulty ?? .gentle), game: old, now: now)
        if old.isSolved { library.markSolved(id: id, at: now) }
        entryID = id
        var fresh = VisionSaveSlot()
        fresh.entryID = id
        fresh.cursor = slot.cursor
        slotStore.wrappedValue = fresh
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

    private func stageForScreenshots() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--vision-tour") {
            Task { @MainActor in await self.runTour() }
            return
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
        if case .free(let band) = entry.kind { difficulty = band }
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
        guard canUndo, var g = game,
              let move = g.undo(elapsed: g.timer.elapsed(at: Date())) else { return }
        game = g
        cursor = move.cell
        persist()
    }

    /// Off in a co-solve: the undo stack is the board's, not the player's, so
    /// it would take back somebody else's digit. Erase still works on any cell.
    var canUndo: Bool { !(game?.undoStack.isEmpty ?? true) && !isSolved && !coSolve.isActive }

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
        coSolve.begin(invite: invite, fillable: fillable, accent: accent.rawValue,
                      over: transport)
        let sameBoard = game.map {
            $0.puzzle.seed == invite.seed && $0.puzzle.difficulty == invite.difficulty
        } ?? false
        if sameBoard, !isSolved {
            coSolveReady()
        } else {
            compose(invite.difficulty, seed: invite.seed) { [weak self] in self?.coSolveReady() }
        }
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
        guard var g = game, !isSolved, !g.isGiven(move.cell) else { return }
        let elapsed = g.timer.elapsed(at: Date())
        let index = g.moveLog.count
        coSolve.attribute(seat: 1, firstMoveIndex: index, elapsed: elapsed)
        let changed = move.digit == 0
            ? g.erase(at: move.cell, elapsed: elapsed)
            : g.place(move.digit, at: move.cell, elapsed: elapsed)
        guard changed else { return }
        game = g
        lastEvent = (move.cell, move.digit == 0 ? .erase : (g.isError(at: move.cell) ? .error : .place), Date())
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
        guard coSolve.isShared, let seats = coSolve.seats, let game else { return nil }
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
        reportCoSolve()
        // A board somebody else also filled in is nobody's solve (PRD-27 §7).
        guard !coSolve.isShared else { return }
        recordSolve(game: g, at: now)
    }

    /// One classic solve, into the history every device reads and onto Game
    /// Center — the same `SolveRecord` the phone writes for a free board.
    ///
    /// `nine.history` is one KVS blob under last-writer-wins, and this headset
    /// may hold a stale copy of it. So the write starts from the newest copy
    /// KVS has and folds this headset's in (`SolveHistory.merged`): writing
    /// back cannot drop a solve the phone recorded since the headset last
    /// looked.
    private func recordSolve(game g: NineGame, at now: Date) {
        let seconds = g.timer.elapsed(at: now)
        let record = SolveRecord(
            date: now, difficulty: difficulty, isDaily: false, seconds: seconds,
            points: SolveScore.points(difficulty: difficulty, isDaily: false,
                                      streak: 0, seconds: seconds),
            errors: g.errorCount)
        var history = historyStore.wrappedValue
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = kvs.data(forKey: CouchKeyspace.namespacedKey("nine.history")),
           let shared = try? CouchJSON.decode(SolveHistory.self, from: data) {
            history = shared.merged(with: history)
        }
        history.record(record)
        historyStore.wrappedValue = history
        try? historyStore.flushNow()
        GameCenter.shared.reportSolve(record: record, history: history)
    }

    private func persist() {
        if let game, let id = entryID, var entry = library.entry(id: id) {
            entry.game = game
            entry.updatedAt = Date()
            library.upsert(entry)
            cloudStore?.push(entry)
        }
        saveSlot()
        reportCoSolve()
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

    /// Only with an iCloud account signed in — the same gate `AppModel` uses.
    private func setUpCloudSyncIfAvailable() {
        guard cloudStore == nil, FileManager.default.ubiquityIdentityToken != nil else { return }
        let store = LibraryCloudStore()
        store.onRemoteEntry = { [weak self] synced in self?.applyRemoteEntry(synced) }
        store.onRemoteDeletion = { [weak self] id in self?.applyRemoteDeletion(id) }
        store.onAccountReset = { [weak self] in self?.repushEntireLibrary() }
        // Replays are not kept on this target (no comet to draw them with), so
        // `onRemoteReplay` stays unset and a replay record is simply skipped.
        cloudStore = store
        store.start()
        if !store.hasSyncedBefore { repushEntireLibrary() }
    }

    private func repushEntireLibrary() {
        for entry in library.entries { cloudStore?.push(entry) }
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
        if entryID == id { entryID = nil }
    }

    /// After a merge: if this board moved elsewhere, show where it is now; if
    /// the player is idle on a board another device has since moved past, go
    /// to that one — the phone's board, waiting in the room.
    private func refreshAfterMerge() {
        guard !coSolve.isActive else { return }
        if let id = entryID, let merged = library.entry(id: id),
           let game, merged.game.entries != game.entries || merged.status == .solved {
            let wasSolved = isSolved
            open(merged, cursor: cursor)
            if !wasSolved, isSolved { winningCell = nil }
        }
        guard cursor == nil, let newest = library.mostRecentFreePartial, newest.id != entryID
        else { return }
        let current = entryID.flatMap(library.entry(id:))
        if current == nil || current?.status != .inProgress
            || newest.updatedAt > (current?.updatedAt ?? .distantPast) {
            open(newest, cursor: nil)
        }
    }
}
#endif
