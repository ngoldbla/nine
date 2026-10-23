// VisionApp.swift — Nine on Vision Pro, entry point.
//
// One plain window holding the board alone; no immersive space, no shelf, no
// settings. SharePlay shares that same window rather than opening a space. The board is the shipped `BoardView` — the same Canvas, the same
// accessibility tree, the same Metal Afterglow — so the only code new to this
// platform is input, two ornaments and the spark burst.
#if os(visionOS)
import SwiftUI
import CouchKit
import GroupActivities

@main
struct NineVisionApp: App {
    /// Installed before any state exists — position is the mechanism, exactly
    /// as in `NineApp.swift` and `WatchApp.swift`. A fourth process, so a
    /// fourth install site.
    private let phrasebook: Void = Strings.install()

    @State private var model = VisionModel()

    var body: some Scene {
        WindowGroup {
            VisionBoardScreen()
                .environment(model)
                // SharePlay: a session started from "Play together", or
                // accepted from somebody else's, joins the board here.
                .task {
                    for await session in NineCoSolveActivity.sessions() {
                        await model.join(session)
                    }
                }
        }
        // `.plain`: the board brings its own slab of glass, and a window
        // background behind it would be glass on glass.
        .windowStyle(.plain)
        .windowResizability(.contentSize)
    }
}
#endif
