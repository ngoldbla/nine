// RemoteRoseTests — the TV rose's swipe-then-tap grammar, pinned.
//
// No simulator can put a thumb on a Siri Remote, so the reconciliation between
// tvOS's four-way move commands and RemoteKit's eight-way strokes is asserted
// here, against the event orders a real remote produces: move commands during
// the stroke, the stroke itself on lift.
import XCTest
@testable import NineShared

final class RemoteRoseTests: XCTestCase {

    // MARK: RoseFocus

    func testAFreshRoseFocusesFive() {
        XCTAssertEqual(RoseFocus().digit, 5)
    }

    func testMoveCommandsAloneWalkFourWay() {
        // The Simulator's arrow keys and a first-generation remote: no strokes.
        var focus = RoseFocus()
        focus.swipe(dx: 0, dy: -1, at: 0)
        XCTAssertEqual(focus.digit, 2)
        focus.swipe(dx: -1, dy: 0, at: 1.5)
        XCTAssertEqual(focus.digit, 1)
        focus.swipe(dx: -1, dy: 0, at: 3)
        XCTAssertEqual(focus.digit, 1, "focus clamps to the keypad")
    }

    func testADiagonalStrokeSettlesOnTheCorner() {
        // A swipe up-left: tvOS reports "up" mid-stroke, the lift says up-left.
        var focus = RoseFocus()
        focus.swipe(dx: 0, dy: -1, at: 10.0)
        XCTAssertEqual(focus.digit, 2, "the ring answers the thumb at once")
        focus.stroke(dx: -1, dy: -1, at: 10.3)
        XCTAssertEqual(focus.digit, 1, "and settles where the stroke pointed")
    }

    func testACardinalStrokeDoesNotDoubleStep() {
        var focus = RoseFocus()
        focus.swipe(dx: 1, dy: 0, at: 0)
        focus.stroke(dx: 1, dy: 0, at: 0.2)
        XCTAssertEqual(focus.digit, 6, "one swipe is one step, not two")
    }

    func testAStrokeWithNoMoveCommandStillSteps() {
        // A short diagonal can classify without tvOS ever issuing a move.
        var focus = RoseFocus()
        focus.stroke(dx: 1, dy: 1, at: 0)
        XCTAssertEqual(focus.digit, 9)
    }

    func testASecondSwipeIsRelativeToWhereTheFirstLanded() {
        var focus = RoseFocus()
        focus.swipe(dx: 0, dy: 1, at: 0)
        focus.stroke(dx: 0, dy: 1, at: 0.2)
        XCTAssertEqual(focus.digit, 8)
        // The opposite swipe returns to the centre, so 5 is never stranded.
        focus.swipe(dx: 0, dy: -1, at: 2)
        focus.stroke(dx: 0, dy: -1, at: 2.2)
        XCTAssertEqual(focus.digit, 5)
    }

    func testALateStrokeDoesNotRewindAnOldSwipe() {
        var focus = RoseFocus()
        focus.swipe(dx: 0, dy: -1, at: 0)
        // Well past the window: this stroke is its own swipe.
        focus.stroke(dx: -1, dy: 0, at: 5)
        XCTAssertEqual(focus.digit, 1)
    }

    // MARK: PrimaryPressGate

    func testATapAndAClickOnOneThumbAreOnePress() {
        var gate = PrimaryPressGate()
        XCTAssertTrue(gate.accept(.tap, at: 0))
        XCTAssertFalse(gate.accept(.click, at: 0.1))
        var reversed = PrimaryPressGate()
        XCTAssertTrue(reversed.accept(.click, at: 0))
        XCTAssertFalse(reversed.accept(.tap, at: 0.2))
    }

    func testTwoQuickTapsAreTwoPresses() {
        // Open the rose, then place 5.
        var gate = PrimaryPressGate()
        XCTAssertTrue(gate.accept(.tap, at: 0))
        XCTAssertTrue(gate.accept(.tap, at: 0.2))
    }

    func testAClickWellAfterATapActs() {
        var gate = PrimaryPressGate()
        XCTAssertTrue(gate.accept(.tap, at: 0))
        XCTAssertTrue(gate.accept(.click, at: 1))
    }

    // MARK: BackGuard

    func testOneBackArmsAndTwoLeave() {
        var guardrail = BackGuard()
        XCTAssertFalse(guardrail.press(at: 0))
        XCTAssertTrue(guardrail.isArmed)
        XCTAssertTrue(guardrail.press(at: 1))
        XCTAssertFalse(guardrail.isArmed)
    }

    func testASlowSecondBackOnlyRearms() {
        var guardrail = BackGuard()
        XCTAssertFalse(guardrail.press(at: 0))
        XCTAssertFalse(guardrail.press(at: 10))
        XCTAssertTrue(guardrail.press(at: 11))
    }

    func testAnythingInBetweenDisarms() {
        var guardrail = BackGuard()
        XCTAssertFalse(guardrail.press(at: 0))
        guardrail.disarm()
        XCTAssertFalse(guardrail.press(at: 0.5), "Back, move, Back is not a double press")
    }
}
