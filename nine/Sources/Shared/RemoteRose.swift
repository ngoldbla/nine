// RemoteRose.swift — how the Apple TV remote picks a petal (1.3 TV input pass).
//
// The TV rose is now driven the way a player's thumb already wants to drive it:
// **swipe to a petal, tap to place it.** Nothing commits on a swipe. That is a
// reversal of the old grammar, where a clean eight-way flick placed its digit
// the instant the finger lifted — fast for the one player who had learned it,
// and a misplaced digit for everybody who was only trying to *look* at a petal.
//
// Two input streams describe the same swipe, and this file is where they are
// reconciled:
//
//   • tvOS's move command (`onMoveCommand`) — four-way, fires *during* the
//     stroke, and is the only thing a first-generation remote or the
//     Simulator's arrow keys ever produce. Applied at once so the ring answers
//     the thumb immediately.
//   • RemoteKit's analog stroke — eight-way, fires when the finger *lifts*.
//     It is the only stream that can say "up-left", so when it arrives it is
//     authoritative for the swipe it ends: focus rewinds to where the swipe
//     began and takes one eight-way step from there.
//
// For a cardinal swipe the two agree and the rewind is invisible. For a
// diagonal the ring visits the cardinal petal for the length of the stroke and
// settles on the corner when the finger lifts — the stroke's own geometry
// deciding, never a guess.
//
// Linux-clean on purpose (no SwiftUI, no CouchKit): the remote grammar is the
// one part of the TV that no simulator can drive with a real thumb, so it is the
// part that has to be checkable without one.
import Foundation

/// The focused petal of an open TV rose, in keypad order (0 = digit 1 at the
/// top-left, 4 = digit 5 in the centre, 8 = digit 9 at the bottom-right).
struct RoseFocus: Equatable, Sendable {
    /// How long after the last move command a stroke still counts as the end
    /// of that same swipe. A slow, deliberate swipe on a Siri Remote takes a
    /// few hundred milliseconds from the move command to the lift.
    static let strokeWindow: TimeInterval = 0.9

    private(set) var index: Int
    /// Where focus stood before the swipe in progress began moving it. Nil
    /// between swipes.
    private var swipeOrigin: Int?
    private var lastSwipeAt: TimeInterval = -.infinity

    /// A freshly opened rose focuses the centre petal, so a tap with no swipe
    /// places 5 — the same digit the centre of the keypad has always meant.
    init(index: Int = 4) {
        self.index = Self.clamp(index)
    }

    /// The digit a tap would place right now.
    var digit: Int { index + 1 }

    /// One four-way move command. `dx`/`dy` are −1, 0 or 1 with screen-down
    /// positive.
    mutating func swipe(dx: Int, dy: Int, at time: TimeInterval) {
        if swipeOrigin == nil || time - lastSwipeAt > Self.strokeWindow {
            swipeOrigin = index
        }
        lastSwipeAt = time
        index = Self.step(index, dx: dx, dy: dy)
    }

    /// One completed analog stroke, eight-way. Rewinds whatever the move
    /// commands of the same swipe did, then takes exactly one step.
    mutating func stroke(dx: Int, dy: Int, at time: TimeInterval) {
        var from = index
        if let origin = swipeOrigin, time - lastSwipeAt <= Self.strokeWindow {
            from = origin
        }
        swipeOrigin = nil
        index = Self.step(from, dx: dx, dy: dy)
    }

    private static func step(_ index: Int, dx: Int, dy: Int) -> Int {
        let row = min(2, max(0, index / 3 + dy.signum()))
        let column = min(2, max(0, index % 3 + dx.signum()))
        return row * 3 + column
    }

    private static func clamp(_ index: Int) -> Int { min(8, max(0, index)) }
}

/// One press of the remote's primary action, from either of the two things
/// that can mean it: a light **tap** on the touch surface, or a **click**.
///
/// RemoteKit already refuses to report a tap for a touch that clicked, but the
/// two edges come from different subsystems (GameController sees the lift,
/// UIKit sees the press) and their order is not promised. This gate is the
/// belt to that pair of braces: a tap and a click that land within `window` of
/// each other are one press, so the rose can never open and commit on a single
/// thumb.
struct PrimaryPressGate: Sendable {
    enum Source: Equatable, Sendable { case tap, click }

    static let window: TimeInterval = 0.35

    private var last: (source: Source, time: TimeInterval)?

    init() {}

    /// Whether this press should act. Two presses of the *same* kind always
    /// act — a quick tap to open the rose and a second tap to place 5 is a
    /// real thing players do.
    mutating func accept(_ source: Source, at time: TimeInterval) -> Bool {
        defer { last = (source, time) }
        guard let last else { return true }
        return last.source == source || time - last.time > Self.window
    }
}

/// The in-game Back button, which no longer leaves a board on one press.
///
/// A gamepad's Circle reaches UIKit as Menu as well as reaching PadKit as
/// Circle, and Circle is undo. The 1.2 playtest found the result: a player
/// pressing undo was thrown out to the shelf. The tvOS input pass closes that
/// for every source at once — the first Back on a quiet board only *arms* the
/// exit and says so; a second Back inside `window` leaves. Nothing is lost
/// either way (leaving saves), so the cost of the second press is one press,
/// and the cost of not having it was the board.
struct BackGuard: Equatable, Sendable {
    static let window: TimeInterval = 2.5

    private var armedAt: TimeInterval?

    init() {}

    var isArmed: Bool { armedAt != nil }

    /// Returns true when this Back should leave the board.
    mutating func press(at time: TimeInterval) -> Bool {
        if let armedAt, time - armedAt <= Self.window {
            self.armedAt = nil
            return true
        }
        armedAt = time
        return false
    }

    /// Anything else the player does disarms it: a Back, then a move, then a
    /// Back is two separate thoughts, not a double press.
    mutating func disarm() { armedAt = nil }

    /// Whether the arming has expired by `time` (for clearing the chip).
    func hasExpired(at time: TimeInterval) -> Bool {
        guard let armedAt else { return true }
        return time - armedAt > Self.window
    }
}
