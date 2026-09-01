import XCTest

@MainActor
final class StorageInteractionTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testDownloadsQuotaReclaimAndStorageFlows() throws {
        launchStorageProfile(.pausedActiveQueue)
        openSurface(
            control: "playstead.control.open-downloads",
            root: "playstead.surface.downloads"
        )

        harness.require([
            "playstead.downloads.summary",
            "playstead.download.row.0",
            "playstead.download.row.0.state",
            "playstead.download.row.0.pause-resume",
            "playstead.download.row.1",
            "playstead.download.row.2"
        ])
        XCTAssertEqual(elements("playstead.download.row").count, 3)
        assertValue("playstead.downloads.summary", equals: "1 downloading, 1 queued, 1 paused")
        assertValue("playstead.download.row.0.state", equals: "active")
        assertValue("playstead.download.row.1.state", equals: "paused")
        assertValue("playstead.download.row.2.state", equals: "waiting")

        harness.focusContainedAction(
            "playstead.download.row.0.pause-resume",
            rootIdentifier: "playstead.surface.downloads"
        )
        harness.element("playstead.download.row.0.pause-resume", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.download.row.0.state", equals: "paused")
        XCTAssertEqual(elements("playstead.download.state.paused").count, 2)

        harness.focusContainedAction(
            "playstead.download.row.0.pause-resume",
            rootIdentifier: "playstead.surface.downloads"
        )
        harness.element("playstead.download.row.0.pause-resume", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.download.row.0.state", equals: "waiting")
        XCTAssertEqual(elements("playstead.download.state.paused").count, 1)
        XCTAssertEqual(elements("playstead.download.state.waiting").count, 2)

        harness.validateSemanticTargets([
            .init("playstead.download.row.0.pause-resume", type: .button),
            .init("playstead.download.row.0.cancel", type: .button),
            .init("playstead.download.row.0.move-up", type: .button),
            .init("playstead.download.row.0.move-down", type: .button)
        ])
        try harness.audit(.action, rootIdentifier: "playstead.surface.downloads")
        XCTAssertFalse(harness.sanitizedTrace().isEmpty)
    }

    private func launchStorageProfile(_ profile: UITestHarness.Profile) {
        harness?.app.terminate()
        harness = UITestHarness(profile: profile)
        harness.launch(settledAt: "playstead.surface.library")
    }

    private func openSurface(control: String, root: String) {
        harness.element(control, type: .button).click()
        XCTAssertTrue(harness.element(root).waitForExistence(timeout: 5))
    }

    private func elements(_ identifierPrefix: String) -> [XCUIElement] {
        harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .allElementsBoundByIndex
            .filter { $0.identifier.split(separator: ".").count == identifierPrefix.split(separator: ".").count + 1 }
    }

    private func assertValue(_ identifier: String, equals expected: String) {
        let element = harness.element(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing value element: \(identifier)")
        XCTAssertEqual(element.value as? String, expected)
    }

    private func waitForValue(_ identifier: String, equals expected: String) {
        let element = harness.element(identifier)
        let settled = NSPredicate { _, _ in element.value as? String == expected }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        XCTAssertEqual(element.value as? String, expected)
    }
}
