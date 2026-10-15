// The open Duo's photograph rig (PRD-37), pinned without a simulator.
//
// Taps do not reach the open iPhone Duo's inner panel (Apple 187148389), so
// `shotlist.py --device duo-open` reaches each surface by launch argument
// instead. These pin the parse; `DebugSurfaceSealTests` pins that none of it
// can reach Release.
#if DEBUG
import XCTest
@testable import NineShared

final class DebugSurfaceTests: XCTestCase {

    func testEachSurfaceIsNamedByItsArgument() {
        for surface in DebugSurface.allCases {
            XCTAssertEqual(
                DebugSurface.requested(in: ["Nine", "-NineDebugSurface", surface.rawValue]),
                surface)
        }
        XCTAssertEqual(Set(DebugSurface.allCases.map(\.rawValue)),
                       ["prefs", "history", "boards", "tutorial", "school", "coach", "drawer"])
    }

    /// No argument is today's launch, and so is anything the rig does not
    /// know: a typo must not open some other surface.
    func testAnythingElseIsAnOrdinaryLaunch() {
        XCTAssertNil(DebugSurface.requested(in: ["Nine"]))
        XCTAssertNil(DebugSurface.requested(in: ["Nine", "-NineDebugSurface"]))
        XCTAssertNil(DebugSurface.requested(in: ["Nine", "-NineDebugSurface", "Prefs"]))
        XCTAssertNil(DebugSurface.requested(in: ["Nine", "-NineDebugSurface", "rose"]))
        XCTAssertNil(DebugSurface.requested(in: ["Nine", "prefs"]))
    }

    /// The screen each surface is opened from, which decides whether the
    /// harness launches onto the board or the shelf. Settings is the game
    /// screen's sheet, the one `shotlist.py`'s `prefs` scene photographs.
    func testEachSurfaceKnowsItsScreen() {
        XCTAssertEqual(DebugSurface.allCases.filter { $0.onGameScreen },
                       [.prefs, .coach, .drawer])
    }
}
#endif
