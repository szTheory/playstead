import XCTest

@MainActor
final class SurfaceAccessibilityTests: XCTestCase {
    private var harness: UITestHarness!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testLibrarySidebarUsesIndependentFocusAndLiveAudit() throws {
        harness = UITestHarness(profile: "populated-curation-reorder")
        harness.launch(settledAt: "playstead.surface.library")

        let requiredRoutes = [
            "playstead.surface.library",
            "playstead.surface.sidebar",
            "playstead.surface.search",
            "playstead.surface.filter",
            "playstead.surface.game-list"
        ]
        harness.require(requiredRoutes)

        let exactFocusOrder = [
            "playstead.control.open-downloads",
            "playstead.control.open-storage",
            "playstead.control.open-adapter"
        ]
        harness.traverseExactFocusSequence(exactFocusOrder, activate: exactFocusOrder[0])
        XCTAssertTrue(harness.element("playstead.surface.downloads").waitForExistence(timeout: 5))

        harness.element("playstead.control.done", type: .button).typeKey(.space, modifierFlags: [])
        harness.element("playstead.control.open-downloads", type: .button).click()
        XCTAssertTrue(harness.element("playstead.surface.downloads").waitForExistence(timeout: 5))
        harness.element("playstead.control.done", type: .button).click()

        try harness.audit([
            .init("playstead.control.open-downloads", type: .button),
            .init("playstead.control.open-storage", type: .button),
            .init("playstead.control.open-adapter", type: .button),
            .init("library.search.field", type: .textField, requiresValue: true)
        ])
        XCTAssertFalse(harness.sanitizedTrace().isEmpty)
    }

    func testContextualRoutesContainAndRestoreFocus() throws {
        harness = UITestHarness(profile: "storage")
        harness.launch(settledAt: "playstead.surface.library")

        let opener = harness.element("playstead.control.open-adapter", type: .button)
        opener.click()
        harness.require(["playstead.surface.adapter"])
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.adapter")
        harness.app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))
        XCTAssertTrue(opener.value(forKey: "hasKeyboardFocus") as? Bool == true)

        harness.element("playstead.control.open-readiness", type: .button).click()
        harness.require(["playstead.surface.readiness"])
        harness.element("playstead.control.open-bios", type: .button).click()
        harness.require(["playstead.surface.bios"])
        harness.element("playstead.control.open-controller-settings", type: .button).click()
        harness.require(["playstead.surface.controller-settings"])
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.readiness")
        harness.element("playstead.control.done", type: .button).typeKey(.space, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.readiness").waitForExistence(timeout: 2))

        try harness.audit([
            .init("playstead.control.open-adapter", type: .button),
            .init("playstead.control.open-readiness", type: .button),
            .init("playstead.control.open-bios", type: .button),
            .init("playstead.control.open-controller-settings", type: .button)
        ])
    }
}
