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

    func testLibraryRouteInventorySettlesOnProductionProfile() {
        launchLibrary(profile: .populatedCurationReorder)
        harness.require([
            "playstead.surface.library",
            "playstead.surface.sidebar",
            "playstead.surface.search",
            "playstead.surface.filter",
            "playstead.surface.game-card",
            "library.search.field"
        ])
    }

    func testLibraryFocusSequenceWrapsAndActivatesList() {
        launchLibrary(profile: .populatedCurationReorder)
        let exactFocusOrder = [
            "playstead.control.show-cards",
            "playstead.control.show-list",
            "playstead.control.open-readiness"
        ]
        harness.traverseExactFocusSequence(exactFocusOrder, activate: exactFocusOrder[1])
        harness.require(["playstead.surface.game-list"])
    }

    func testDownloadsSheetOpensAndDismisses() {
        launchLibrary(profile: .populatedCurationReorder)
        harness.element("playstead.control.open-downloads", type: .button).click()
        XCTAssertTrue(harness.element("playstead.surface.downloads").waitForExistence(timeout: 5))
        harness.element("playstead.control.done", type: .button).click()
        XCTAssertFalse(harness.element("playstead.surface.downloads").waitForExistence(timeout: 2))
    }

    func testLibrarySemanticTargetsHaveRolesLabelsAndFrames() {
        launchLibrary(profile: .populatedCurationReorder)
        harness.validateSemanticTargets(libraryTargets)
        XCTAssertFalse(harness.sanitizedTrace().isEmpty)
    }

    func testLibraryContrastAccessibilityAudit() throws { try auditLibrary(.contrast) }
    func testLibraryElementDetectionAccessibilityAudit() throws { try auditLibrary(.elementDetection) }
    func testLibraryHitRegionAccessibilityAudit() throws { try auditLibrary(.hitRegion) }
    func testLibrarySufficientDescriptionAccessibilityAudit() throws { try auditLibrary(.sufficientElementDescription) }
    func testLibraryActionAccessibilityAudit() throws { try auditLibrary(.action) }
    func testLibraryParentChildAccessibilityAudit() throws { try auditLibrary(.parentChild) }

    func testContextualOpenersHaveRolesLabelsAndFrames() {
        launchLibrary(profile: .storage)
        harness.validateSemanticTargets(contextualOpenerTargets)
    }

    func testContextualOpenersContrastAccessibilityAudit() throws { try auditContextualOpeners(.contrast) }
    func testContextualOpenersElementDetectionAccessibilityAudit() throws { try auditContextualOpeners(.elementDetection) }
    func testContextualOpenersHitRegionAccessibilityAudit() throws { try auditContextualOpeners(.hitRegion) }
    func testContextualOpenersSufficientDescriptionAccessibilityAudit() throws { try auditContextualOpeners(.sufficientElementDescription) }
    func testContextualOpenersActionAccessibilityAudit() throws { try auditContextualOpeners(.action) }
    func testContextualOpenersParentChildAccessibilityAudit() throws { try auditContextualOpeners(.parentChild) }

    func testAdapterSheetContainsKeyboardFocus() {
        _ = launchAdapterSheet()
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.adapter")
    }

    func testAdapterSheetDismissesWithEscape() {
        _ = launchAdapterSheet()
        harness.app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))
    }

    func testAdapterSheetRestoresOpenerFocusAfterEscape() {
        let opener = launchAdapterSheet()
        harness.app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))
        XCTAssertTrue(opener.value(forKey: "hasKeyboardFocus") as? Bool == true)
    }

    func testAdapterControlsHaveRolesLabelsAndFrames() {
        _ = launchAdapterSheet()
        harness.validateSemanticTargets(adapterTargets)
    }

    func testAdapterContrastAccessibilityAudit() throws { try auditAdapter(.contrast) }
    func testAdapterElementDetectionAccessibilityAudit() throws { try auditAdapter(.elementDetection) }
    func testAdapterHitRegionAccessibilityAudit() throws { try auditAdapter(.hitRegion) }
    func testAdapterSufficientDescriptionAccessibilityAudit() throws { try auditAdapter(.sufficientElementDescription) }
    func testAdapterActionAccessibilityAudit() throws { try auditAdapter(.action) }
    func testAdapterParentChildAccessibilityAudit() throws { try auditAdapter(.parentChild) }

    func testReadinessRoutesReachBIOSAndControllerSettings() {
        launchReadinessRoutes()
    }

    func testReadinessSheetContainsKeyboardFocus() {
        launchReadinessRoutes()
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.readiness")
    }

    func testReadinessDoneActionReceivesKeyboardFocus() {
        launchReadinessRoutes()
        harness.focusContainedAction(
            "playstead.control.done",
            rootIdentifier: "playstead.surface.readiness"
        )
    }

    func testReadinessDoneActionDismissesSheet() {
        launchReadinessRoutes()
        harness.focusContainedAction(
            "playstead.control.done",
            rootIdentifier: "playstead.surface.readiness"
        )
        harness.element("playstead.control.done", type: .button).typeKey(.space, modifierFlags: [])
        XCTAssertFalse(harness.element("playstead.surface.readiness").waitForExistence(timeout: 2))
    }

    func testReadinessControlsHaveRolesLabelsAndFrames() {
        launchReadinessRoutes()
        harness.validateSemanticTargets(readinessTargets)
    }

    func testReadinessContrastAccessibilityAudit() throws { try auditReadiness(.contrast) }
    func testReadinessElementDetectionAccessibilityAudit() throws { try auditReadiness(.elementDetection) }
    func testReadinessHitRegionAccessibilityAudit() throws { try auditReadiness(.hitRegion) }
    func testReadinessSufficientDescriptionAccessibilityAudit() throws { try auditReadiness(.sufficientElementDescription) }
    func testReadinessActionAccessibilityAudit() throws { try auditReadiness(.action) }
    func testReadinessParentChildAccessibilityAudit() throws { try auditReadiness(.parentChild) }

    private var libraryTargets: [UITestHarness.AuditTarget] {
        [
            .init("playstead.control.open-downloads", type: .button),
            .init("playstead.control.open-storage", type: .button),
            .init("playstead.control.open-adapter", type: .button),
            .init("playstead.control.show-cards", type: .button),
            .init("playstead.control.show-list", type: .button),
            .init("library.search.field", type: .textField)
        ]
    }

    private var contextualOpenerTargets: [UITestHarness.AuditTarget] {
        [
            .init("playstead.control.open-adapter", type: .button),
            .init("playstead.control.open-readiness", type: .button)
        ]
    }

    private var adapterTargets: [UITestHarness.AuditTarget] {
        [
            .init("playstead.control.install-adapter", type: .button),
            .init("playstead.control.choose-adapter", type: .button)
        ]
    }

    private var readinessTargets: [UITestHarness.AuditTarget] {
        [
            .init("playstead.control.open-bios", type: .button),
            .init("playstead.control.open-controller-settings", type: .button),
            .init("playstead.control.choose-bios", type: .button)
        ]
    }

    private func auditLibrary(_ category: UITestHarness.AuditCategory) throws {
        launchLibrary(profile: .populatedCurationReorder)
        try harness.audit(category, rootIdentifier: "playstead.surface.library")
    }

    private func auditContextualOpeners(_ category: UITestHarness.AuditCategory) throws {
        launchLibrary(profile: .storage)
        try harness.audit(category, rootIdentifier: "playstead.surface.library")
    }

    private func auditAdapter(_ category: UITestHarness.AuditCategory) throws {
        _ = launchAdapterSheet()
        try harness.audit(category, rootIdentifier: "playstead.surface.adapter")
    }

    private func auditReadiness(_ category: UITestHarness.AuditCategory) throws {
        launchReadinessRoutes()
        try harness.audit(category, rootIdentifier: "playstead.surface.readiness")
    }

    private func launchLibrary(profile: UITestHarness.Profile) {
        harness = UITestHarness(profile: profile)
        harness.launch(settledAt: "playstead.surface.library")
    }

    @discardableResult
    private func launchAdapterSheet() -> XCUIElement {
        launchLibrary(profile: .storage)
        let opener = harness.element("playstead.control.open-adapter", type: .button)
        opener.click()
        harness.require(["playstead.surface.adapter"])
        return opener
    }

    private func launchReadinessRoutes() {
        launchLibrary(profile: .storage)
        harness.element("playstead.control.open-readiness", type: .button).click()
        harness.require(["playstead.surface.readiness"])
        harness.element("playstead.control.open-bios", type: .button).click()
        harness.require(["playstead.surface.bios"])
        harness.element("playstead.control.open-controller-settings", type: .button).click()
        harness.require(["playstead.surface.controller-settings"])
    }
}
