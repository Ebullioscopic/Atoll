import XCTest

final class CodeIslandCompanionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuestionStateRendersPrimaryControls() throws {
        let app = launchApp(mockState: "question")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["companion.questionCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["companion.command.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.command.skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.liveActivity.inlineButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLongMessageStateCanScrollToRecentActivity() throws {
        let app = launchApp(mockState: "long")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))

        let messages = app.otherElements["companion.messages"]
        if !messages.waitForExistence(timeout: 4) {
            app.scrollViews["companion.scroll"].swipeUp()
        }
        XCTAssertTrue(messages.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["companion.liveActivity.primaryButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIdleStateKeepsMacAndLiveActivityActionsReachable() throws {
        let app = launchApp(mockState: "idle")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["companion.command.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.liveActivity.primaryButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeMultiSessionShowsBoard() throws {
        let app = launchApp(mockState: "multi")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.otherElements["companion.standby.board"].waitForExistence(timeout: 8))
        let rows = app.otherElements.matching(identifier: "companion.standby.sessionRow")
        XCTAssertGreaterThanOrEqual(rows.count, 2)
    }

    @MainActor
    private func launchApp(mockState: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CodeIslandCompanionMockState", mockState]
        app.launch()
        return app
    }
}
