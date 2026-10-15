// DebugSurfaceRig.swift — the App half of `-NineDebugSurface` (PRD-37).
//
// `DebugSurface` parses the argument; this spends it. Once per process, so a
// photograph launch opens its surface on arrival and the shelf or board it
// came from behaves normally after that — going home and back does not
// reopen History. Debug builds only (`DebugSurfaceSealTests`).
#if DEBUG
import Foundation

@MainActor
enum DebugSurfaceLatch {
    private static var spent = false

    /// The requested surface if `screen` owns it and it has not been opened yet.
    static func take(onGameScreen screen: Bool) -> DebugSurface? {
        guard !spent, let surface = DebugSurface.requested(),
              surface.onGameScreen == screen else { return nil }
        spent = true
        return surface
    }

    /// A beat after arrival: the fold is published from the root's first
    /// layout pass, and a surface opened before it lands would be laid out for
    /// no fold and then move.
    static func afterArrival(_ open: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            open()
        }
    }
}
#endif
