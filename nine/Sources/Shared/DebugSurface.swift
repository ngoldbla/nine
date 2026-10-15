// DebugSurface.swift — open one surface at launch, for the photograph rig (PRD-37).
//
// Neither taps nor the accessibility bridge reach the open iPhone Duo's inner
// panel (Apple 187148389), so `shotlist.py --device duo-open` cannot drive to
// a sheet the way every other lane does. It launches with
// `-NineDebugSurface <name>` instead, and the view that owns that surface
// opens it once. Debug builds only — `DebugSurfaceSealTests` fails if any of
// this escapes `#if DEBUG` — and with no argument nothing here runs.
//
// The names are a harness's vocabulary, never shown to a player.
#if DEBUG
import Foundation

public enum DebugSurface: String, CaseIterable, Sendable {
    /// The game screen's Settings sheet, the one `shotlist.py`'s `prefs` photographs.
    case prefs
    case history, boards, tutorial, school
    /// A hint's coach card, on the resumed board.
    case coach
    /// The stats drawer, pulled down over the board.
    case drawer

    /// The surface named by `-NineDebugSurface <name>`, or nil — no argument,
    /// no value, or a name this enum does not know.
    public static func requested(
        in arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> DebugSurface? {
        guard let flag = arguments.firstIndex(of: "-NineDebugSurface"),
              flag + 1 < arguments.count else { return nil }
        return DebugSurface(rawValue: arguments[flag + 1])
    }

    /// Opened from the board (launched with resume on) rather than the shelf.
    public var onGameScreen: Bool {
        switch self {
        case .prefs, .coach, .drawer: return true
        case .history, .boards, .tutorial, .school: return false
        }
    }
}
#endif
