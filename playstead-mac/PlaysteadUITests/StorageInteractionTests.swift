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
        XCTAssertEqual(elementCount(withValue: "paused"), 2)

        harness.focusContainedAction(
            "playstead.download.row.0.pause-resume",
            rootIdentifier: "playstead.surface.downloads"
        )
        harness.element("playstead.download.row.0.pause-resume", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.download.row.0.state", equals: "waiting")
        XCTAssertEqual(elementCount(withValue: "paused"), 1)
        XCTAssertEqual(elementCount(withValue: "waiting"), 2)

        harness.validateSemanticTargets([
            .init("playstead.download.row.0.pause-resume", type: .button),
            .init("playstead.download.row.0.cancel", type: .button),
            .init("playstead.download.row.0.move-up", type: .button),
            .init("playstead.download.row.0.move-down", type: .button)
        ])
        try harness.audit(.action, rootIdentifier: "playstead.surface.downloads")
        XCTAssertFalse(harness.sanitizedTrace().isEmpty)

        exerciseQuotaAndFocusRestoration()
        try exerciseReclaimPrompt()
        try exerciseStorageInventory()
    }

    private func exerciseQuotaAndFocusRestoration() {
        launchStorageProfile(.quotaBlockReclaim)
        let opener = harness.element("playstead.control.open-storage", type: .button)
        openSurface(
            control: "playstead.control.open-storage",
            root: "playstead.surface.storage"
        )
        harness.require([
            "playstead.quota.root",
            "playstead.quota.state",
            "playstead.quota.increase",
            "playstead.quota.decrease"
        ])
        assertValue(
            "playstead.quota.state",
            equals: "used=32;quota=16;floor=10737418240"
        )
        harness.focusContainedAction(
            "playstead.quota.increase",
            rootIdentifier: "playstead.surface.storage"
        )
        harness.element("playstead.quota.increase", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue(
            "playstead.quota.state",
            equals: "used=32;quota=1073741840;floor=10737418240"
        )
        dismissSheet(root: "playstead.surface.storage")
        XCTAssertTrue(opener.value(forKey: "hasKeyboardFocus") as? Bool == true)
    }

    private func exerciseReclaimPrompt() throws {
        launchStorageProfile(.quotaBlockReclaim)
        harness.traverseExactFocusSequence(
            [
                "playstead.control.show-cards",
                "playstead.control.show-list",
                "playstead.control.open-readiness"
            ],
            activate: "playstead.control.show-list"
        )
        focusAndActivateButton(label: "Download")

        let reclaimRoot = harness.element("playstead.surface.reclaim")
        XCTAssertTrue(reclaimRoot.waitForExistence(timeout: 5))
        harness.require([
            "playstead.reclaim.shortfall",
            "playstead.reclaim.candidate.0",
            "playstead.reclaim.candidate.0.toggle",
            "playstead.reclaim.confirm",
            "playstead.reclaim.cancel"
        ])
        assertValue("playstead.reclaim.shortfall", equals: "48")
        assertValue("playstead.reclaim.selection", equals: "count=0;bytes=0")

        harness.focusContainedAction(
            "playstead.reclaim.candidate.0.toggle",
            rootIdentifier: "playstead.surface.reclaim"
        )
        harness.element("playstead.reclaim.candidate.0.toggle", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.reclaim.selection", equals: "count=1;bytes=32")
        harness.focusContainedAction(
            "playstead.reclaim.confirm",
            rootIdentifier: "playstead.surface.reclaim"
        )
        harness.element("playstead.reclaim.confirm", type: .button)
            .typeKey(.space, modifierFlags: [])

        // The 16-byte quota still blocks the 32-byte target after reclaim,
        // so the real retry reopens with no eligible cached rows. This is
        // an exact, observable proof that 32 bytes were removed and the
        // target was not silently treated as downloaded.
        XCTAssertTrue(reclaimRoot.waitForExistence(timeout: 5))
        waitForValue("playstead.reclaim.shortfall", equals: "16")
        waitForValue("playstead.reclaim.selection", equals: "count=0;bytes=0")
        XCTAssertEqual(elements("playstead.reclaim.candidate").count, 0)
        harness.validateSemanticTargets([
            .init("playstead.reclaim.cancel", type: .button)
        ])
        try harness.audit(.action, rootIdentifier: "playstead.surface.reclaim")
        harness.focusContainedAction(
            "playstead.reclaim.cancel",
            rootIdentifier: "playstead.surface.reclaim"
        )
        harness.element("playstead.reclaim.cancel", type: .button)
            .typeKey(.space, modifierFlags: [])
        XCTAssertFalse(reclaimRoot.waitForExistence(timeout: 2))
        XCTAssertTrue(harness.app.staticTexts["Synthetic Reclaim Candidate"].exists)
        XCTAssertTrue(harness.app.staticTexts["Synthetic Quota Download"].exists)
    }

    private func exerciseStorageInventory() throws {
        launchStorageProfile(.quotaBlockReclaim)
        openSurface(
            control: "playstead.control.open-storage",
            root: "playstead.surface.storage"
        )
        harness.require([
            "playstead.storage.inventory",
            "playstead.storage.state",
            "playstead.storage.candidate.0",
            "playstead.storage.candidate.0.toggle",
            "playstead.storage.reclaim"
        ])
        assertValue(
            "playstead.storage.state",
            equals: "used=32;candidate-count=1;pinned-count=0;unreferenced-count=0;quarantined-count=0"
        )
        harness.focusContainedAction(
            "playstead.storage.candidate.0.toggle",
            rootIdentifier: "playstead.surface.storage"
        )
        harness.element("playstead.storage.candidate.0.toggle", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.storage.selection", equals: "count=1;bytes=32")
        harness.focusContainedAction(
            "playstead.storage.reclaim",
            rootIdentifier: "playstead.surface.storage"
        )
        harness.element("playstead.storage.reclaim", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue(
            "playstead.storage.state",
            equals: "used=0;candidate-count=0;pinned-count=0;unreferenced-count=0;quarantined-count=0"
        )
        XCTAssertEqual(elements("playstead.storage.candidate").count, 0)
        try harness.audit(.action, rootIdentifier: "playstead.surface.storage")
        dismissSheet(root: "playstead.surface.storage")
        XCTAssertTrue(harness.app.staticTexts["Synthetic Reclaim Candidate"].exists)
        XCTAssertTrue(harness.app.staticTexts["Synthetic Quota Download"].exists)

        launchStorageProfile(.storage)
        openSurface(
            control: "playstead.control.open-storage",
            root: "playstead.surface.storage"
        )
        assertValue(
            "playstead.storage.state",
            equals: "used=32;candidate-count=0;pinned-count=1;unreferenced-count=0;quarantined-count=0"
        )
        harness.require(["playstead.storage.pinned.0"])
        XCTAssertEqual(elements("playstead.storage.candidate").count, 0)
        XCTAssertFalse(harness.element("playstead.storage.reclaim", type: .button).isEnabled)
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

    private func dismissSheet(root: String) {
        harness.focusContainedAction(
            "playstead.control.done",
            rootIdentifier: root
        )
        harness.element("playstead.control.done", type: .button)
            .typeKey(.space, modifierFlags: [])
        XCTAssertFalse(harness.element(root).waitForExistence(timeout: 2))
    }

    private func focusAndActivateButton(label: String) {
        let target = harness.app.buttons[label]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            if target.value(forKey: "hasKeyboardFocus") as? Bool == true {
                target.typeKey(.space, modifierFlags: [])
                return
            }
            harness.app.typeKey(.tab, modifierFlags: [])
        }
        XCTFail("Tab never reached button labelled \(label)")
    }

    private func elements(_ identifierPrefix: String) -> [XCUIElement] {
        harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .allElementsBoundByIndex
            .filter { $0.identifier.split(separator: ".").count == identifierPrefix.split(separator: ".").count + 1 }
    }

    private func elementCount(withValue value: String) -> Int {
        harness.app.staticTexts
            .matching(NSPredicate(format: "value == %@", value))
            .allElementsBoundByIndex.count
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
