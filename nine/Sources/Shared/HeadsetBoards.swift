// HeadsetBoards.swift — which board Vision Pro opens, as pure rules.
//
// Lifted out of `VisionModel` so `swift test` can hold them: the model is an
// `@Observable` on a visionOS-only target, and the rules are a function of the
// library alone.
//
// **Classic only, explicitly.** A channel board's rules (`channelRules`) live in
// a local-only blob on the device that composed it — they do not sync — so a
// Thermo or Killer board reaching the headset by CloudKit would draw as a plain
// sudoku, cages and thermometers missing, and be solvable against the wrong
// rules. `mostRecentFreePartial` already kept the idle switch on classic; the
// remembered-board path did not ask. Co-solve invites cannot carry a channel
// board at all (`ParlorInvite` is a seed and a classic band).
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// Where the player left off on this headset (`nine.vision.board`): which
/// library board, and the cursor on it. The board itself is in `nine.library`.
///
/// `game` and `difficulty` are the pre-sync slot's fields, read once to move a
/// board saved by the first, local-only build into the library
/// (`HeadsetBoards.migrate`), and never written again.
public struct VisionSaveSlot: Codable, Sendable, Equatable {
    public var entryID: UUID?
    public var cursor: Int?
    public var game: NineGame?
    public var difficulty: Difficulty?

    public init() {}

    enum CodingKeys: String, CodingKey { case entryID, cursor, game, difficulty }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryID = (try? c.decodeIfPresent(UUID.self, forKey: .entryID)) ?? nil
        cursor = (try? c.decodeIfPresent(Int.self, forKey: .cursor)) ?? nil
        game = (try? c.decodeIfPresent(NineGame.self, forKey: .game)) ?? nil
        // `try?` because a future band this build cannot name must not throw
        // the board away with it.
        difficulty = (try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? nil
    }
}

public enum HeadsetBoards {

    /// The first build saved one board, locally, in the slot. Move it into the
    /// library once — a free board in its band (Gentle if it had none), solved
    /// if it was — and return the slot to write instead, which names the entry
    /// and drops the old fields. Nil when there is nothing to move.
    public static func migrate(_ slot: VisionSaveSlot, into library: inout BoardLibrary,
                               now: Date) -> VisionSaveSlot? {
        guard slot.entryID == nil, let old = slot.game else { return nil }
        let id = library.create(kind: .free(slot.difficulty ?? .gentle), game: old, now: now)
        if old.isSolved { library.markSolved(id: id, at: now) }
        var fresh = VisionSaveSlot()
        fresh.entryID = id
        fresh.cursor = slot.cursor
        return fresh
    }

    /// Whether the headset can draw this board faithfully.
    public static func isPlayable(_ kind: GameKind) -> Bool {
        switch kind {
        case .free, .daily: return true
        case .channel(let channel, _, _): return channel.variant == .classic
        }
    }

    /// The board to open at launch: the one this headset was on, if it is
    /// still here and playable (solved included — it reopens solved), else the
    /// newest classic board in progress. Nil means compose a fresh one.
    public static func atLaunch(_ library: BoardLibrary, remembered: UUID?) -> LibraryEntry? {
        if let id = remembered, let entry = library.entry(id: id), isPlayable(entry.kind) {
            return entry
        }
        return library.mostRecentFreePartial
    }

    /// After a merge: a classic board in progress that has moved past the one
    /// on the headset — the phone's board, waiting in the room — or nil.
    /// "Past" means the current board is gone, finished, or older.
    public static func newerBoard(in library: BoardLibrary, current: UUID?) -> LibraryEntry? {
        guard let newest = library.mostRecentFreePartial, newest.id != current,
              isPlayable(newest.kind) else { return nil }
        guard let current = current.flatMap(library.entry(id:)), current.status == .inProgress
        else { return newest }
        return newest.updatedAt > current.updatedAt ? newest : nil
    }
}
