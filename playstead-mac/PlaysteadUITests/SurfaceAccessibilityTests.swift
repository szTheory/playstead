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
            "playstead.surface.filter",
            "playstead.surface.game-card"
        ])
        validateNativeSearchField()
    }

    func testLibraryListRadioControlOpensAndArrowKeysSelectRows() {
        launchLibrary(profile: .populatedCurationReorder)
        harness.element("playstead.control.show-list", type: .radioButton).clickWhenHittable()
        harness.require(["playstead.surface.game-list"])
        let list = harness.element("playstead.surface.game-list")
        let initialSelection = list.value as? String
        XCTAssertFalse(initialSelection?.isEmpty ?? true, "the production list should expose its selected title")
        waitForKeyboardFocus(list, stage: "library-list-arrow-focus")
        list.typeKey(.downArrow, modifierFlags: [])
        let changed = NSPredicate { _, _ in list.value as? String != initialSelection }
        let selectedAnotherRow = XCTNSPredicateExpectation(predicate: changed, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedAnotherRow], timeout: 5), .completed)
    }

    func testDownloadsSidebarRouteOpensAndReturnsToLibrary() {
        launchLibrary(profile: .populatedCurationReorder)
        selectSidebar("Downloads")
        XCTAssertTrue(harness.element("playstead.surface.downloads").awaitExistence(timeout: 5))
        selectSidebar("All Games")
        XCTAssertFalse(harness.element("playstead.surface.downloads").waitForExistence(timeout: 2))
        XCTAssertTrue(harness.element("playstead.surface.library").awaitExistence(timeout: 5))
    }

    func testLibrarySemanticTargetsHaveRolesLabelsAndFrames() {
        launchLibrary(profile: .populatedCurationReorder)
        harness.validateSemanticTargets(libraryTargets)
        validateNativeSearchField()
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

    func testAdapterSettingsContainsKeyboardFocus() {
        _ = launchAdapterSettings()
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.adapter")
    }

    func testAdapterSettingsRouteReturnsToStoragePane() {
        _ = launchAdapterSettings()
        harness.element("playstead.control.open-storage", type: .radioButton).clickWhenHittable()
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))
        XCTAssertTrue(harness.element("playstead.surface.storage").awaitExistence(timeout: 5))
    }

    func testAdapterSettingsRouteReturnsToLibrary() {
        _ = launchAdapterSettings()
        selectSidebar("All Games")
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))
        XCTAssertTrue(harness.element("playstead.surface.library").awaitExistence(timeout: 5))
    }

    func testAdapterControlsHaveRolesLabelsAndFrames() {
        _ = launchAdapterSettings()
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
        harness.require(["playstead.surface.bios"])
        harness.element("playstead.control.done", type: .button).clickWhenHittable()
        XCTAssertFalse(harness.element("playstead.surface.readiness").waitForExistence(timeout: 2))
        selectSidebar("Settings")
        harness.element("playstead.control.open-controller-settings", type: .radioButton).clickWhenHittable()
        harness.require(["playstead.surface.controller-settings"])
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
            "playstead.surface.filter",
            "playstead.surface.game-list", "playstead.surface.game-card",
            "playstead.surface.downloads", "playstead.quota.root",
            "playstead.surface.storage", "playstead.surface.reclaim",
            "playstead.surface.readiness", "playstead.surface.adapter",
            "playstead.surface.bios", "playstead.surface.controller-settings"
        ])
        XCTAssertEqual(expectedSurfaces.count, 19, "D-18 surface inventory must stay nonempty and unique")

        launchLibrary(profile: .populatedCurationReorder)
        recordRequired([
            "playstead.surface.library", "playstead.surface.sidebar",
            "playstead.surface.filter",
            "playstead.surface.game-card"
        ], in: &visited)
        harness.validateSemanticTargets(libraryTargets)
        harness.element("playstead.control.show-list", type: .radioButton).clickWhenHittable()
        recordRequired(["playstead.surface.game-list"], in: &visited)
        try auditEveryCategory(root: "playstead.surface.library")

        for (label, root) in [
            ("Recently Played", "playstead.surface.shelf.continue"),
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
        XCTAssertTrue(collection.awaitExistence(timeout: 5))
        collection.clickWhenHittable()
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
        XCTAssertTrue(memberList.awaitExistence(timeout: 5))
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

        harness.app.terminate()
        launchLibrary(profile: .pausedActiveQueue)
        selectSidebar("Downloads")
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
        selectSidebar("All Games")
        XCTAssertFalse(harness.element("playstead.surface.downloads").waitForExistence(timeout: 2))

        harness.app.terminate()
        launchLibrary(profile: .quotaBlockReclaim)
        selectSidebar("Settings")
        harness.element("playstead.control.open-storage", type: .radioButton).clickWhenHittable()
        recordRequired(["playstead.quota.root", "playstead.surface.storage"], in: &visited)
        harness.validateSemanticTargets([
            .init("playstead.quota.decrease", type: .button),
            .init("playstead.quota.increase", type: .button),
            .init("playstead.storage.candidate.0.toggle", type: .button),
            .init("playstead.storage.reclaim", type: .button)
        ])
        try auditEveryCategory(root: "playstead.surface.storage")
        selectSidebar("All Games")
        XCTAssertFalse(harness.element("playstead.surface.storage").waitForExistence(timeout: 2))

        harness.element("playstead.control.show-list", type: .radioButton).clickWhenHittable()
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

        harness.app.terminate()
        launchLibrary(profile: .storage)
        selectSidebar("Settings")
        harness.element("playstead.control.open-adapter", type: .radioButton).clickWhenHittable()
        recordRequired(["playstead.surface.adapter"], in: &visited)
        harness.validateSemanticTargets(adapterTargets)
        harness.traverseExactFocusSequence(
            ["playstead.control.install-adapter", "playstead.control.choose-adapter"],
            activate: "playstead.control.install-adapter",
            failureStage: "all-surface-adapter-actions",
            rootIdentifier: "playstead.surface.adapter"
        )
        try auditEveryCategory(root: "playstead.surface.adapter")
        selectSidebar("All Games")
        XCTAssertFalse(harness.element("playstead.surface.adapter").waitForExistence(timeout: 2))

        harness.app.terminate()
        launchReadinessRoutes()
        recordRequired(["playstead.surface.readiness", "playstead.surface.bios"], in: &visited)
        harness.validateSemanticTargets(readinessTargets)
        try auditEveryCategory(root: "playstead.surface.readiness")
        harness.assertSheetFocusContained(rootIdentifier: "playstead.surface.readiness")
        harness.element("playstead.control.done", type: .button).clickWhenHittable()
        XCTAssertFalse(harness.element("playstead.surface.readiness").waitForExistence(timeout: 2))
        selectSidebar("Settings")
        harness.element("playstead.control.open-controller-settings", type: .radioButton).clickWhenHittable()
        recordRequired(["playstead.surface.controller-settings"], in: &visited)
        try auditEveryCategory(root: "playstead.surface.controller-settings")

        XCTAssertEqual(visited, expectedSurfaces, "D-18 routes drifted from the independent inventory")
        XCTAssertFalse(harness.sanitizedTrace().isEmpty, "live-tree evidence must be non-vacuous")
    }

    private var libraryTargets: [UITestHarness.AuditTarget] {
        [
            .init("playstead.control.show-cards", type: .radioButton),
            .init("playstead.control.show-list", type: .radioButton)
        ]
    }

    private func validateNativeSearchField() {
        let field = harness.app.searchFields.firstMatch
        XCTAssertTrue(field.awaitExistence(timeout: 5), "the native searchable field should be exposed")
        XCTAssertEqual(field.elementType, .searchField)
        let accessibleName = field.placeholderValue ?? ""
        XCTAssertFalse(accessibleName.isEmpty, "the native search field needs an accessible label or prompt")
        let frame = field.frame
        let components = [frame.origin.x, frame.origin.y, frame.width, frame.height]
        XCTAssertTrue(
            frame.width > 0 && frame.height > 0 && components.allSatisfy(\.isFinite),
            "native search field has no usable frame"
        )
    }

    private var contextualOpenerTargets: [UITestHarness.AuditTarget] {
        [
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
            .init("playstead.readiness.row.bios.remedy", type: .button),
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
        _ = launchAdapterSettings()
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
    private func launchAdapterSettings() -> XCUIElement {
        launchLibrary(profile: .storage)
        selectSidebar("Settings")
        let adapterPane = harness.element("playstead.control.open-adapter", type: .radioButton)
        adapterPane.clickWhenHittable()
        harness.require(["playstead.surface.adapter"])
        return adapterPane
    }

    private func launchReadinessRoutes() {
        launchLibrary(profile: .biosAcceptance)
        harness.element("playstead.control.open-readiness", type: .button).clickWhenHittable()
        harness.require(["playstead.surface.readiness"])
        let biosRemedy = harness.element("playstead.readiness.row.bios.remedy", type: .button)
        XCTAssertTrue(biosRemedy.awaitExistence(timeout: 5))
        let readinessContent = harness.element("playstead.readiness.content")
        // The fixture intentionally has several blockers before BIOS in the
        // production readiness order. Reach the real remedy through the
        // focused sheet's scroll view before activating it.
        for _ in 0..<6 where !biosRemedy.isHittable {
            readinessContent.swipeUp()
        }
        biosRemedy.clickWhenHittable()
        harness.require(["playstead.surface.bios"])
    }

    private func recordRequired(_ identifiers: [String], in visited: inout Set<String>) {
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertTrue(visited.isDisjoint(with: identifiers), "a D-18 surface was counted twice")
        harness.require(identifiers)
        visited.formUnion(identifiers)
    }

    private func selectSidebar(_ label: String) {
        let identifiers = [
            "All Games": "playstead.sidebar.home",
            "Recently Played": "playstead.sidebar.continue",
            "Favorites": "playstead.sidebar.favorites",
            "Collections": "playstead.sidebar.collections",
            "Queue": "playstead.sidebar.queue",
            "Recent": "playstead.sidebar.recent",
            "Downloads": "playstead.sidebar.downloads",
            "Settings": "playstead.sidebar.settings"
        ]
        guard let identifier = identifiers[label] else {
            return XCTFail("sidebar destination is not part of the test-owned inventory: \(label)")
        }
        let destination = harness.element(identifier, type: .staticText)
        XCTAssertTrue(destination.awaitExistence(timeout: 5), "sidebar destination missing: \(label)")
        destination.clickWhenHittable()
    }

    private func selectQuotaDownloadByKeyboard() {
        let gameList = "playstead.surface.game-list"
        let initialList = harness.element(gameList)
        XCTAssertTrue(initialList.awaitExistence(timeout: 5))
        XCTAssertEqual(initialList.value as? String, "Synthetic Quota Download")
        waitForKeyboardFocus(initialList, stage: "quota-list-keyboard-focus")
        initialList.typeKey(.downArrow, modifierFlags: [])
        waitForLibraryListValue(gameList, equals: "Synthetic Reclaim Candidate", stage: "quota-list-down-arrow-selection")
        harness.element(gameList).typeKey(.upArrow, modifierFlags: [])
        waitForLibraryListValue(gameList, equals: "Synthetic Quota Download", stage: "quota-list-up-arrow-selection")
        let command = harness.element("playstead.control.download-selected", type: .button)
        XCTAssertTrue(command.awaitExistence(timeout: 5))
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

    private func waitForLibraryListValue(_ identifier: String, equals expected: String, stage: String) {
        let settled = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let current = self.harness.element(identifier)
            guard current.exists else { return false }
            return current.value as? String == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, stage)
        let current = harness.element(identifier)
        XCTAssertTrue(current.awaitExistence(timeout: 5), stage)
        XCTAssertEqual(current.value as? String, expected, stage)
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
