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

    /// Downstream D-18 aggregation. This inventory is intentionally authored
    /// here instead of importing `AccessibilityIdentifiers.all` or deriving
    /// expected order from the live tree.
    func testKeyboardOnlySurfaceInventoryAndLiveAudit() throws {
        var visited = Set<String>()
        let expectedSurfaces = Set([
            "playstead.surface.library", "playstead.surface.sidebar",
            "playstead.surface.shelf.continue", "playstead.surface.shelf.favorites",
            "playstead.surface.collections", "playstead.surface.collection-detail",
            "playstead.surface.shelf.play-queue", "playstead.surface.shelf.recent",
            "playstead.surface.search", "playstead.surface.filter",
            "playstead.surface.game-list", "playstead.surface.game-card",
            "playstead.surface.downloads", "playstead.quota.root",
            "playstead.surface.storage", "playstead.surface.reclaim",
            "playstead.surface.readiness", "playstead.surface.adapter",
            "playstead.surface.bios", "playstead.surface.controller-settings"
        ])
        XCTAssertEqual(expectedSurfaces.count, 20, "D-18 surface inventory must stay nonempty and unique")

        launchLibrary(profile: .populatedCurationReorder)
        recordRequired([
            "playstead.surface.library", "playstead.surface.sidebar",
            "playstead.surface.search", "playstead.surface.filter",
            "playstead.surface.game-card"
        ], in: &visited)
        harness.validateSemanticTargets(libraryTargets)
        harness.traverseExactFocusSequence(
            [
                "playstead.control.show-cards",
                "playstead.control.show-list",
                "playstead.control.open-readiness"
            ],
            activate: "playstead.control.show-list",
            failureStage: "all-surface-library-layout"
        )
        recordRequired(["playstead.surface.game-list"], in: &visited)
        try auditEveryCategory(root: "playstead.surface.library")

        for (label, root) in [
            ("Continue", "playstead.surface.shelf.continue"),
            ("Favorites", "playstead.surface.shelf.favorites"),
            ("Queue", "playstead.surface.shelf.play-queue"),
            ("Recent", "playstead.surface.shelf.recent")
        ] {
            selectSidebar(label)
            recordRequired([root], in: &visited)
            try auditEveryCategory(root: root)
        }

        harness.app.terminate()
        launchLibrary(profile: .populatedCurationReorder)
        selectSidebar("Collections")
        recordRequired(["playstead.surface.collections"], in: &visited)
        let collection = harness.element(
            "playstead.curation.collection.00000000-0000-7000-8000-000000000200",
            type: .button
        )
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        collection.click()
        recordRequired(["playstead.surface.collection-detail"], in: &visited)
        let memberIDs = (1...3).map { "00000000-0000-7000-8000-00000000020\($0)" }
        let collectionControls = [
            "playstead.curation.collection-command.move-up",
            "playstead.curation.collection-command.move-down"
        ] + memberIDs.flatMap { memberID in
            [
                "playstead.curation.collection-member.\(memberID).move-up",
                "playstead.curation.collection-member.\(memberID).move-down"
            ]
        }
        harness.validateSemanticTargets(collectionControls.map { .init($0, type: .button) })
        let memberList = harness.element("playstead.curation.collection-member-list")
        XCTAssertTrue(memberList.waitForExistence(timeout: 5))
        waitForKeyboardFocus(memberList, stage: "all-surface-collection-list-focus")
        let selection = harness.element("playstead.curation.collection-selection")
        for _ in 0..<3 where selection.value as? String != memberIDs[2] {
            memberList.typeKey(.downArrow, modifierFlags: [])
        }
        waitForValue(
            selection,
            equals: memberIDs[2],
            stage: "all-surface-collection-last-member-selection"
        )
        // A macOS SwiftUI List owns arrow-key focus as one control; its row
        // actions are semantic audit targets, not an independent Tab ring.
        // Exercise the production command-bar shortcut used by the focused
        // List and prove the selected member actually settles at the edge.
        let selectedMoveUp = harness.element(
            "playstead.curation.collection-command.move-up",
            type: .button
        )
        let selectedMoveDown = harness.element(
            "playstead.curation.collection-command.move-down",
            type: .button
        )
        XCTAssertTrue(selectedMoveUp.isEnabled, "all-surface-collection-selected-move-up-disabled")
        XCTAssertFalse(selectedMoveDown.isEnabled, "all-surface-collection-last-member-move-down-enabled")
        harness.app.typeKey("u", modifierFlags: [.command, .option])
        waitForValue(
            harness.element("playstead.test.curation.evidence"),
            equals: curationEvidence(order: [memberIDs[0], memberIDs[2], memberIDs[1]], outboxCount: 1),
            stage: "all-surface-collection-keyboard-reorder-not-settled"
        )
        XCTAssertTrue(selectedMoveDown.isEnabled, "all-surface-collection-selected-move-down-lost")
        XCTAssertTrue(selectedMoveUp.isEnabled, "all-surface-collection-selected-move-up-lost")
        XCTAssertEqual(
            selection.value as? String,
            memberIDs[2],
            "all-surface-collection-selection-lost-after-reorder"
        )
        try auditEveryCategory(root: "playstead.surface.collection-detail")

        launchLibrary(profile: .pausedActiveQueue)
        let downloadsOpener = harness.element("playstead.control.open-downloads", type: .button)
        downloadsOpener.click()
        recordRequired(["playstead.surface.downloads"], in: &visited)
        let downloadControls = (0...2).flatMap { slot in
            [
                "playstead.download.row.\(slot).pause-resume",
                "playstead.download.row.\(slot).cancel",
                "playstead.download.row.\(slot).move-up",
                "playstead.download.row.\(slot).move-down"
            ]
        }
        harness.validateSemanticTargets(downloadControls.map { .init($0, type: .button) })
        try auditEveryCategory(root: "playstead.surface.downloads")
        dismissSheet(root: "playstead.surface.downloads", opener: downloadsOpener)

        launchLibrary(profile: .quotaBlockReclaim)
        let storageOpener = harness.element("playstead.control.open-storage", type: .button)
        storageOpener.click()
        recordRequired(["playstead.quota.root", "playstead.surface.storage"], in: &visited)
        harness.validateSemanticTargets([
            .init("playstead.quota.decrease", type: .button),
            .init("playstead.quota.increase", type: .button),
            .init("playstead.storage.candidate.0.toggle", type: .button),
            .init("playstead.storage.reclaim", type: .button)
        ])
        try auditEveryCategory(root: "playstead.surface.storage")
        dismissSheet(root: "playstead.surface.storage", opener: storageOpener)

        harness.traverseExactFocusSequence(
            [
                "playstead.control.show-cards",
                "playstead.control.show-list",
                "playstead.control.open-readiness"
            ],
            activate: "playstead.control.show-list",
            failureStage: "all-surface-quota-list"
        )
        selectQuotaDownloadByKeyboard()
        harness.app.typeKey("d", modifierFlags: [.command])
        recordRequired(["playstead.surface.reclaim"], in: &visited)
        harness.validateSemanticTargets([
            .init("playstead.reclaim.raise-quota", type: .button),
            .init("playstead.reclaim.candidate.0.toggle", type: .button),
            .init("playstead.reclaim.confirm", type: .button),
            .init("playstead.reclaim.cancel", type: .button)
        ])
        try auditEveryCategory(root: "playstead.surface.reclaim")

        launchLibrary(profile: .storage)
        let adapterOpener = harness.element("playstead.control.open-adapter", type: .button)
        adapterOpener.click()
        recordRequired(["playstead.surface.adapter"], in: &visited)
        harness.validateSemanticTargets(adapterTargets)
        harness.traverseExactFocusSequence(
            ["playstead.control.install-adapter", "playstead.control.choose-adapter"],
            activate: "playstead.control.install-adapter",
            failureStage: "all-surface-adapter-actions"
        )
        try auditEveryCategory(root: "playstead.surface.adapter")
        dismissSheet(root: "playstead.surface.adapter", opener: adapterOpener)

        launchReadinessRoutes()
        recordRequired([
            "playstead.surface.readiness", "playstead.surface.bios",
            "playstead.surface.controller-settings"
        ], in: &visited)
        harness.validateSemanticTargets(readinessTargets)
        try auditEveryCategory(root: "playstead.surface.readiness")
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.readiness")

        XCTAssertEqual(visited, expectedSurfaces, "D-18 routes drifted from the independent inventory")
        XCTAssertFalse(harness.sanitizedTrace().isEmpty, "live-tree evidence must be non-vacuous")
    }

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

    private func recordRequired(_ identifiers: [String], in visited: inout Set<String>) {
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertTrue(visited.isDisjoint(with: identifiers), "a D-18 surface was counted twice")
        harness.require(identifiers)
        visited.formUnion(identifiers)
    }

    private func selectSidebar(_ label: String) {
        let destination = harness.app.staticTexts[label]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "sidebar destination missing: \(label)")
        destination.click()
    }

    private func dismissSheet(root: String, opener: XCUIElement) {
        harness.focusContainedAction("playstead.control.done", rootIdentifier: root)
        harness.element("playstead.control.done", type: .button).typeKey(.space, modifierFlags: [])
        XCTAssertFalse(harness.element(root).waitForExistence(timeout: 2))
        XCTAssertTrue(opener.value(forKey: "hasKeyboardFocus") as? Bool == true)
    }

    private func selectQuotaDownloadByKeyboard() {
        let assetID = "00000000-0000-7000-8000-000000000042"
        let list = harness.element("playstead.surface.game-list")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let selection = harness.element("playstead.library.list-selection")
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        for _ in 0..<2 where selection.value as? String != assetID {
            list.typeKey(.downArrow, modifierFlags: [])
        }
        XCTAssertEqual(selection.value as? String, assetID)
        let command = harness.element("playstead.control.download-selected", type: .button)
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        XCTAssertTrue(command.isEnabled)
    }

    private func auditEveryCategory(root: String) throws {
        for category in UITestHarness.AuditCategory.allCases {
            try harness.audit(category, rootIdentifier: root)
        }
    }

    private func waitForKeyboardFocus(_ element: XCUIElement, stage: String) {
        let focused = NSPredicate { _, _ in element.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let expectation = XCTNSPredicateExpectation(predicate: focused, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, stage)
    }

    private func waitForValue(_ element: XCUIElement, equals expected: String, stage: String) {
        let settled = NSPredicate { _, _ in element.value as? String == expected }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, stage)
        XCTAssertEqual(element.value as? String, expected, stage)
    }

    private func curationEvidence(order: [String], outboxCount: Int) -> String {
        let catalogueFingerprint = [
            "72cd6e8422c407fb6d098690f1130b7ded7ec2f7f5e1d30bd9d521f015363793",
            "75877bb41d393b5fb8455ce60ecd8dda001d06316496b14dfa7f895656eeca4a",
            "648aa5c579fb30f38af744d97d6ec840c7a91277a499a0d780f3e7314eca090b"
        ].sorted().joined(separator: ",")
        return "order=\(order.joined(separator: ","));outbox=\(outboxCount);catalogue=\(catalogueFingerprint)"
    }
}
