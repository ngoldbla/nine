// ShelfDoorTests.swift — every door on the Apple TV opens *and closes* with
// the Siri Remote, pressed through the real focus engine.
//
// These exist because the 1.2 beta shipped two doors a remote could not use:
// Boards and History opened behind the shelf's glass row, which kept focus, so
// Back closed the row and left the sheet up with nothing on screen able to
// reach it — and on History, nothing able to leave it at all. A unit test of
// the handlers cannot see that; only a press that goes where focus goes can.
import XCTest

final class ShelfDoorTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        // The first-run card's one Button has default focus; a click takes it.
        let start = app.buttons["Start playing"]
        if start.waitForExistence(timeout: 4) {
            remote.press(.select)
            XCTAssertTrue(start.waitForNonExistence(timeout: 4), "the welcome card did not close")
        }
        // Nine reopens the board a player left, and an earlier test may have
        // left one. Back closes the rose, then two Backs save and go home.
        for _ in 0..<4 where onBoard {
            remote.press(.menu)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertFalse(onBoard, "could not get from the board to the shelf")
        // Let the shelf's surface claim focus after the card's fade.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Whether the board is on screen: its squares are accessibility buttons.
    private var onBoard: Bool { app.buttons["Row 1, column 1"].exists }

    // MARK: - Boards

    func testBoardsOpensAndClosesWithBack() {
        openShelfDoor(index: 0)
        let close = app.buttons["Close boards"]
        XCTAssertTrue(close.waitForExistence(timeout: 4), "Boards did not open")
        // Focus nowhere is how Back used to leave the app from here.
        XCTAssertTrue(close.hasFocus, "Boards opened without taking focus")
        // Focus must be inside the sheet: a move lands on one of its controls
        // rather than walking the shelf behind it.
        remote.press(.down)
        XCTAssertTrue(app.buttons["Close boards"].exists)
        remote.press(.menu)
        XCTAssertTrue(close.waitForNonExistence(timeout: 4), "Back did not close Boards")
        assertShelfIsLive()
    }

    func testBoardsOpensAgainAfterClosing() {
        openShelfDoor(index: 0)
        XCTAssertTrue(app.buttons["Close boards"].waitForExistence(timeout: 4))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["Close boards"].waitForNonExistence(timeout: 4))
        openShelfDoor(index: 0)
        XCTAssertTrue(app.buttons["Close boards"].waitForExistence(timeout: 4),
                      "Boards would not open a second time")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["Close boards"].waitForNonExistence(timeout: 4))
    }

    // MARK: - History

    func testHistoryOpensScrollsAndClosesWithBack() {
        openShelfDoor(index: 1)
        let close = app.buttons["Close history"]
        XCTAssertTrue(close.waitForExistence(timeout: 4), "History did not open")
        XCTAssertTrue(close.hasFocus, "History opened without taking focus")
        // Walk down the whole sheet and back up: the remote must be able to
        // read every section, and must still be inside the sheet afterwards.
        for _ in 0..<8 { remote.press(.down) }
        for _ in 0..<8 { remote.press(.up) }
        XCTAssertTrue(close.exists, "History closed itself while being read")
        remote.press(.menu)
        XCTAssertTrue(close.waitForNonExistence(timeout: 4), "Back did not close History")
        assertShelfIsLive()
    }

    func testHistoryClosesWithItsCloseButton() {
        openShelfDoor(index: 1)
        let close = app.buttons["Close history"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        // Up from wherever the sheet put focus reaches the close disc at the top.
        for _ in 0..<10 { remote.press(.up) }
        XCTAssertTrue(close.hasFocus, "the close button cannot be reached")
        remote.press(.select)
        XCTAssertTrue(close.waitForNonExistence(timeout: 4), "the close button did not close History")
        assertShelfIsLive()
    }

    // MARK: - In-game settings

    func testHoldingTheClickpadOpensSettingsBesideTheBoard() {
        startBoard()
        remote.press(.select, forDuration: 1.2)
        let remoteGuide = app.buttons["Remote"]
        XCTAssertTrue(remoteGuide.waitForExistence(timeout: 4), "holding the clickpad did not open settings")
        remote.press(.menu)
        XCTAssertTrue(remoteGuide.waitForNonExistence(timeout: 4), "Back did not close settings")
    }

    func testSwipingPastTheBoardsTrailingEdgeOpensSettings() {
        startBoard()
        // The cursor starts in the centre; nine rights carry it past column 9.
        for _ in 0..<9 { remote.press(.right) }
        let remoteGuide = app.buttons["Remote"]
        XCTAssertTrue(remoteGuide.waitForExistence(timeout: 4), "the trailing edge did not open settings")
        remote.press(.menu)
        XCTAssertTrue(remoteGuide.waitForNonExistence(timeout: 4), "Back did not close settings")
    }

    // MARK: - Helpers

    /// A failing press leaves no trace in a log, so a failure keeps the screen
    /// and the element tree it happened on.
    override func record(_ issue: XCTIssue) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.lifetime = .keepAlways
        add(tree)
        if let dir = ProcessInfo.processInfo.environment["NINE_UITEST_DUMP"] {
            let name = "\(dir)/\(self.name.filter { $0.isLetter })"
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: name + ".png"))
            try? app.debugDescription.write(toFile: name + ".txt", atomically: true, encoding: .utf8)
        }
        super.record(issue)
    }

    /// Swipe down to the shelf's glass row, walk right to the door, click it.
    private func openShelfDoor(index: Int) {
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.5)
        for _ in 0..<index { remote.press(.right) }
        remote.press(.select)
    }

    /// The shelf answers the remote again: a swipe down reopens its glass row.
    private func assertShelfIsLive() {
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        remote.press(.down)
        XCTAssertTrue(app.buttons["Boards"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Boards"].hasFocus, "the shelf did not take focus back")
        remote.press(.menu)
    }

    /// Click the shelf's current page and wait for a board to be dealt.
    private func startBoard() {
        remote.press(.select)
        XCTAssertTrue(app.buttons["Row 1, column 1"].waitForExistence(timeout: 15),
                      "no board was dealt")
        // The cursor starts in the centre square.
        Thread.sleep(forTimeInterval: 1)
    }
}
