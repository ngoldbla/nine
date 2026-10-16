// PRD-37's coach drag, pinned by reading the source, because no harness can
// catch the bug this guards against.
//
// `GestureMask.none` is not "this gesture off". Apple: *"Disable all gestures
// in the subview hierarchy, including the added gesture."* Attached to the
// coach card on every non-Duo device, it switched off the card's own action
// button — and the AX trees stayed byte-identical, because VoiceOver
// activation does not go through gestures. `.subviews` is "this gesture off,
// the children's on", which is what a Duo-only drag needs everywhere else.
import XCTest

final class GestureMaskSourceTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SharedTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    func testNoGestureIsAttachedWithAMaskThatDisablesItsSubviews() throws {
        let source = try String(
            contentsOf: Self.nineRoot.appendingPathComponent("Sources/App/TouchUI.swift"),
            encoding: .utf8)
        let offending = source.split(separator: "\n").filter { line in
            line.contains("including:") && line.contains(".none")
        }
        XCTAssertEqual(offending, [],
                       "`including: .none` disables every gesture under the view, its buttons' too; "
                       + "use `.subviews` to switch off only the added gesture")
    }
}
