// VisionCoSolve.swift — SharePlay on Vision Pro: one board, several people's
// hands on it at once, everybody's Persona around the same window.
//
// Built from what the iOS app already has rather than beside it
// (Sources/Shared/CoSolve.swift says why each piece fits):
//
//   * the activity carries a `ParlorInvite` — seed and band, eight bytes and a
//     word — because the board is a pure function of them;
//   * the roster is a `ParlorSession` over the `ParlorTransport` seam, the
//     same type the iOS parlor runs on, so who is here is answered once;
//   * who placed a digit is a `DuelState` over the board's own move log, so
//     the tint is `DuelTint`'s pair and the owner map is `DuelCredits.owners`.
//
// What it does not reuse is `ParlorSession`'s reveal (a co-solve has one time,
// not one each) or `DuelSession` (its hand-off card is the pass-the-remote
// ritual, and it is written against `AppModel`).
//
// **Two seats, not one per person.** You, and everyone else. `DuelTint` proves
// separation for exactly two tints across three dichromacies (PRD-27 §12); a
// third colour would be an untested claim on a headset where the player cannot
// lean in to check. The roster still counts everybody.
#if os(visionOS)
import Foundation
import Observation
import GroupActivities
import CoreTransferable
import CouchKit

// MARK: - The activity

/// The activity every participant is in. Its own type rather than the iOS
/// parlor's `NineParlorActivity`, because the two promise different things: a
/// phone that answered this invitation with a parlor would race a board the
/// headset is sharing.
struct NineCoSolveActivity: GroupActivity {
    static let activityIdentifier = "com.couchsuite.nine.cosolve"

    let invite: ParlorInvite

    var metadata: GroupActivityMetadata {
        var data = GroupActivityMetadata()
        data.title = Strings.string("parlor.activity.title")
        // `.generic`: the shared state is the board, and it travels as moves.
        data.type = .generic
        return data
    }
}

/// What `ShareLink` hands the system so "Play together" can start SharePlay
/// from the window, the visionOS way, without a FaceTime call already open.
struct CoSolveInvitation: Transferable {
    let invite: ParlorInvite

    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { invitation in
            NineCoSolveActivity(invite: invitation.invite)
        }
    }
}

// MARK: - The seam

/// `ParlorTransport`, plus the one thing a parlor never needed: moves.
@MainActor
protocol CoSolveTransport: ParlorTransport {
    var onMove: ((CoSolveMove) -> Void)? { get set }
    var onSnapshot: ((CoSolveSnapshot) -> Void)? { get set }
    func send(_ move: CoSolveMove)
    func send(_ snapshot: CoSolveSnapshot)
}

// MARK: - The session

@MainActor
@Observable
final class VisionCoSolve {
    /// The roster. Its presence is reported (fill and done), never its
    /// finish: a co-solve has one clock, so there is no reveal to hold.
    let parlor = ParlorSession()

    /// The board the room is on, or nil outside SharePlay.
    var invite: ParlorInvite? { parlor.invite }
    var isActive: Bool { parlor.isActive }
    /// Everybody in the call, you included.
    var participantCount: Int { parlor.room?.members.count ?? 0 }

    /// True once somebody else's digit has landed on this board. Such a solve
    /// is nobody's solve — PRD-27 §7's rule for a duel, for the same reason —
    /// so it reaches neither the history nor Game Center.
    private(set) var isShared = false

    /// Who placed what, as turns over the move log. Seat 0 is this headset.
    private(set) var seats: DuelState?

    /// The model applies a remote move to its board and calls `attribute`.
    @ObservationIgnored var onRemoteMove: ((CoSolveMove) -> Void)?

    @ObservationIgnored private var ledger = CoSolveLedger()
    @ObservationIgnored private var transport: (any CoSolveTransport)?
    /// Moves that arrived before this headset's board was composed.
    @ObservationIgnored private var early: [CoSolveMove] = []
    @ObservationIgnored private var boardReady = false
    @ObservationIgnored private var knownRoster: Set<UUID> = []

    /// Join (or start) a co-solve. `boardReady` is false while the joiner is
    /// still composing the invite's board; `ready(ownEntries:)` releases it.
    func begin(invite: ParlorInvite, fillable: Int, accent: String,
               over transport: any CoSolveTransport) {
        end()
        ledger = CoSolveLedger()
        isShared = false
        seats = DuelState(accent: accent, isLight: false, turnLength: .standard)
        self.transport = transport
        transport.onMove = { [weak self] move in self?.receive(move) }
        transport.onSnapshot = { [weak self] snapshot in
            snapshot.moves.forEach { self?.receive($0) }
        }
        parlor.join(invite: invite, fillable: fillable, over: transport)
        // The parlor installed its own roster hook; wrap it so a newcomer is
        // also sent the board so far.
        let parlorRoster = transport.onRoster
        transport.onRoster = { [weak self] ids in
            parlorRoster?(ids)
            self?.rosterChanged(ids)
        }
    }

    /// The board is composed. Whatever this headset already placed on it goes
    /// into the ledger as its own, so a late joiner gets it too.
    func ready(ownEntries: [Int: Int]) {
        guard let transport, !boardReady else { return }
        boardReady = true
        for (cell, digit) in ownEntries.sorted(by: { $0.key < $1.key }) {
            transport.send(ledger.stamp(cell: cell, digit: digit, author: transport.localParticipant))
        }
        let held = early
        early.removeAll()
        held.forEach(receive)
    }

    func end() {
        parlor.leave()
        transport = nil
        early.removeAll()
        boardReady = false
        knownRoster.removeAll()
    }

    /// A digit (or 0 for cleared) set on this headset.
    func send(cell: Int, digit: Int) {
        guard let transport, boardReady else { return }
        transport.send(ledger.stamp(cell: cell, digit: digit, author: transport.localParticipant))
    }

    /// Credit the move about to be logged at `index` to a seat.
    func attribute(seat: Int, firstMoveIndex index: Int, elapsed: TimeInterval) {
        guard var state = seats else { return }
        if state.turns.isEmpty || state.currentPlayer != seat {
            state.beginTurn(player: seat, firstMoveIndex: index, startedAt: elapsed)
            seats = state
        }
        if seat != 0 { isShared = true }
    }

    /// Fill and done, for the roster. Throttled by `ParlorSession.report`.
    func report(fill: Int, done: Bool, fillable: Int) {
        parlor.report(fill: fill, done: done, fillable: fillable)
    }

    var localParticipant: UUID? { transport?.localParticipant }

    private func receive(_ move: CoSolveMove) {
        guard move.author != transport?.localParticipant else { return }
        guard boardReady else { early.append(move); return }
        guard ledger.apply(move) else { return }
        onRemoteMove?(move)
    }

    private func rosterChanged(_ ids: Set<UUID>) {
        defer { knownRoster = ids }
        guard let transport, boardReady, !ids.subtracting(knownRoster).isEmpty,
              !ledger.cells.isEmpty else { return }
        transport.send(ledger.snapshot)
    }
}

// MARK: - The live transport

@MainActor
final class GroupCoSolveTransport: CoSolveTransport {
    let localParticipant: UUID
    var onEnvelope: ((UUID, ParlorEnvelope) -> Void)?
    var onRoster: ((Set<UUID>) -> Void)?
    var onMove: ((CoSolveMove) -> Void)?
    var onSnapshot: ((CoSolveSnapshot) -> Void)?

    private let session: GroupSession<NineCoSolveActivity>
    private let messenger: GroupSessionMessenger
    private var tasks: [Task<Void, Never>] = []

    init(session: GroupSession<NineCoSolveActivity>) {
        self.session = session
        self.messenger = GroupSessionMessenger(session: session)
        self.localParticipant = session.localParticipant.id
        listen()
    }

    /// Ask for the side-by-side template, so every Persona stands on the same
    /// side of the one shared board — what "everyone sees the same board"
    /// means on a headset — and only then join.
    func join() async {
        await Self.preferSideBySide(SessionBox(session: session))
        session.join()
    }

    /// `GroupSession` is not `Sendable` and `systemCoordinator` is a
    /// nonisolated async getter, so Swift 6 refuses the hop from the main
    /// actor. The box makes the one crossing explicit: the coordinator is
    /// configured off the actor and the session is otherwise only touched on it.
    private struct SessionBox: @unchecked Sendable {
        let session: GroupSession<NineCoSolveActivity>
    }

    private nonisolated static func preferSideBySide(_ box: SessionBox) async {
        guard let coordinator = await box.session.systemCoordinator else { return }
        var configuration = SystemCoordinator.Configuration()
        configuration.spatialTemplatePreference = .sideBySide
        coordinator.configuration = configuration
    }

    private func listen() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (envelope, context) in messenger.messages(of: ParlorEnvelope.self) {
                onEnvelope?(context.source.id, envelope)
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (move, _) in messenger.messages(of: CoSolveMove.self) {
                onMove?(move)
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (snapshot, _) in messenger.messages(of: CoSolveSnapshot.self) {
                onSnapshot?(snapshot)
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await participants in session.$activeParticipants.values {
                onRoster?(Set(participants.map(\.id)))
            }
        })
    }

    // Fire-and-forget, like the parlor's: a dropped message is corrected by
    // the next move, or by the snapshot the next newcomer triggers.
    func send(_ envelope: ParlorEnvelope) { Task { try? await messenger.send(envelope) } }
    func send(_ move: CoSolveMove) { Task { try? await messenger.send(move) } }
    func send(_ snapshot: CoSolveSnapshot) { Task { try? await messenger.send(snapshot) } }

    func leave() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        session.leave()
    }
}

// MARK: - The demo transport

#if DEBUG
/// One ghost who solves alongside you, a correct digit every couple of
/// seconds. A FaceTime call cannot be placed into a simulator, so this is the
/// only way the tint, the roster and the no-history rule can be seen running;
/// reached only by `--vision-coplay-demo`, and absent from Release.
@MainActor
final class VisionGhostTransport: CoSolveTransport {
    let localParticipant = UUID(uuidString: "00000000-0000-0000-0000-00000000FACE")!
    var onEnvelope: ((UUID, ParlorEnvelope) -> Void)?
    var onRoster: ((Set<UUID>) -> Void)?
    var onMove: ((CoSolveMove) -> Void)?
    var onSnapshot: ((CoSolveSnapshot) -> Void)?

    private let ghost = UUID(uuidString: "00000000-0000-0000-0000-0000000FEED1")!
    private var clock = 0
    private var ticker: Task<Void, Never>?
    /// The next cell the ghost fills and its digit, or nil when it has none.
    private let nextMove: () -> (cell: Int, digit: Int)?

    init(nextMove: @escaping () -> (cell: Int, digit: Int)?) {
        self.nextMove = nextMove
    }

    func start() {
        onRoster?([localParticipant, ghost])
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let next = nextMove() else { return }
        clock += 1
        onMove?(CoSolveMove(cell: next.cell, digit: next.digit, clock: clock, author: ghost))
    }

    func send(_ envelope: ParlorEnvelope) {}
    func send(_ move: CoSolveMove) { clock = max(clock, move.clock) }
    func send(_ snapshot: CoSolveSnapshot) {}

    func leave() {
        ticker?.cancel()
        ticker = nil
    }
}
#endif
#endif
