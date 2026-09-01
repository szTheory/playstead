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
        harness = UITestHarness(profile: .populatedCurationReorder)
        harness.launch(settledAt: "playstead.surface.library")

        let requiredRoutes = [
            "playstead.surface.library",
            "playstead.surface.sidebar",
            "playstead.surface.search",
            "playstead.surface.filter",
            "playstead.surface.game-card",
            "library.search.field"
        ]
        harness.require(requiredRoutes)

        let exactFocusOrder = [
            "playstead.control.show-cards",
            "playstead.control.show-list",
            "playstead.control.open-readiness"
        ]
        harness.traverseExactFocusSequence(exactFocusOrder, activate: exactFocusOrder[1])
        harness.require(["playstead.surface.game-list"])

        harness.element("playstead.control.open-downloads", type: .button).click()
        XCTAssertTrue(harness.element("playstead.surface.downloads").waitForExistence(timeout: 5))
        harness.element("playstead.control.done", type: .button).click()

        try harness.audit([
            .init("playstead.control.open-downloads", type: .button),
            .init("playstead.control.open-storage", type: .button),
            .init("playstead.control.open-adapter", type: .button),
            .init("playstead.control.show-cards", type: .button),
            .init("playstead.control.show-list", type: .button),
            .init("library.search.field", type: .textField)
        ])
        XCTAssertFalse(harness.sanitizedTrace().isEmpty)
    }

    func testContextualRoutesContainAndRestoreFocus() throws {
        harness = UITestHarness(profile: .storage)
        harness.launch(settledAt: "playstead.surface.library")

        try harness.audit([
            .init("playstead.control.open-adapter", type: .button),
            .init("playstead.control.open-readiness", type: .button)
        ])

        let opener = harness.element("playstead.control.open-adapter", type: .button)
        opener.click()
        harness.require(["playstead.surface.adapter"])
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.adapter")
        try harness.audit([
            .init("playstead.control.install-adapter", type: .button),
            .init("playstead.control.choose-adapter", type: .button)
        ])
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
        try harness.audit([
            .init("playstead.control.open-bios", type: .button),
            .init("playstead.control.open-controller-settings", type: .button),
            .init("playstead.control.choose-bios", type: .button)
        ])
        harness.element("playstead.control.done", type: .button).typeKey(.space, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.readiness").waitForExistence(timeout: 2))
    }
}
