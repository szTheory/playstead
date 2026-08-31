import XCTest

@MainActor
final class HostedRunnerCanaryTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAdHocSignedAppLaunchesOnHostedRunner() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "The ad-hoc-signed Playstead app must launch and expose a window"
        )
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }
}
