import XCTest

@MainActor
final class StorageInteractionTests: XCTestCase {
    private var harness: UITestHarness!
    private let quotaReclaimAssetID = "00000000-0000-7000-8000-000000000041"
    private let quotaDownloadAssetID = "00000000-0000-7000-8000-000000000042"
    private var quotaDownloadAction: String {
        "playstead.game.\(quotaDownloadAssetID).download"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testDownloadsPauseResumeFlow() throws {
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
    }

    func testQuotaEditAndFocusRestoration() {
        exerciseQuotaAndFocusRestoration()
    }

    func testReclaimPromptPresentsProductionRoot() {
        openReclaimPrompt()
    }

    func testReclaimRouteSettlesToUniqueDownloadTrigger() {
        navigateToQuotaFixtureList()
        _ = waitForUniqueDownloadAction()
    }

    func testReclaimRouteKeyboardFocusOwnsUniqueDownloadTrigger() {
        navigateToQuotaFixtureList()
        selectQuotaDownloadByKeyboard()
    }

    func testReclaimRouteDirectActivationDispatchesQuotaEffect() {
        navigateToQuotaFixtureList()
        waitForUniqueDownloadAction().click()
        XCTAssertTrue(
            harness.element("playstead.surface.reclaim").waitForExistence(timeout: 5),
            "direct Download activation did not present the quota reclaim effect"
        )
    }

    func testReclaimRouteActivationDispatchesQuotaEffect() {
        navigateToQuotaFixtureList()
        activateSelectedDownloadByKeyboard()
        XCTAssertTrue(
            harness.element("playstead.surface.reclaim").waitForExistence(timeout: 5),
            "focused Download action did not present the quota reclaim effect"
        )
    }

    func testReclaimPromptInitialStateIsExact() {
        openReclaimPrompt()
        requireInitialReclaimEvidence()
    }

    func testReclaimPromptRowIdentityExists() {
        openReclaimPrompt()
        harness.require(["playstead.reclaim.candidate.0"])
        XCTAssertEqual(elements("playstead.reclaim.candidate").count, 1)
    }

    func testReclaimPromptRowValueIsExact() {
        openReclaimPrompt()
        harness.require(["playstead.reclaim.candidate.0"])
        assertValue("playstead.reclaim.candidate.0", equals: "bytes=32;selected=false")
    }

    func testReclaimPromptToggleBelongsToPrompt() {
        openReclaimPrompt()
        harness.require(["playstead.reclaim.candidate.0.toggle"])
        harness.focusContainedAction(
            "playstead.reclaim.candidate.0.toggle",
            rootIdentifier: "playstead.surface.reclaim"
        )
    }

    func testReclaimPromptSelectionTextTracksExactBytes() {
        openReclaimPrompt()
        selectReclaimCandidate()
    }

    func testReclaimPromptConfirmBecomesEnabled() {
        openReclaimPrompt()
        selectReclaimCandidate()
        assertEnabled("playstead.reclaim.confirm")
    }

    func testReclaimPromptActionsPassLiveAudit() throws {
        openReclaimPrompt()
        selectReclaimCandidate()
        try harness.audit(.action, rootIdentifier: "playstead.surface.reclaim")
    }

    func testReclaimPromptConfirmRemovesExactEligibleBytes() {
        openReclaimPrompt()
        selectReclaimCandidate()
        activateReclaimAndVerifyMutation()
    }

    func testReclaimPromptPostMutationPreservesCanonicalRows() {
        openReclaimPrompt()
        selectReclaimCandidate()
        activateReclaimAndVerifyMutation()
        dismissReclaimAndAssertCanonicalRows()
    }

    func testStorageInventoryPresentsProductionRoot() {
        openEligibleStorageInventory()
        harness.require(["playstead.storage.inventory"])
    }

    func testStorageInventoryRowIdentityExists() {
        openEligibleStorageInventory()
        harness.require(["playstead.storage.candidate.0"])
        XCTAssertEqual(elements("playstead.storage.candidate").count, 1)
    }

    func testStorageInventoryRowValueIsExact() {
        openEligibleStorageInventory()
        harness.require(["playstead.storage.candidate.0"])
        assertValue("playstead.storage.candidate.0", equals: "bytes=32;selected=false")
    }

    func testStorageInventoryToggleBelongsToSurface() {
        openEligibleStorageInventory()
        harness.require(["playstead.storage.candidate.0.toggle"])
        harness.focusContainedAction(
            "playstead.storage.candidate.0.toggle",
            rootIdentifier: "playstead.surface.storage"
        )
    }

    func testStorageInventorySelectionTracksExactBytes() {
        openEligibleStorageInventory()
        requireInitialStorageEvidence()
        selectStorageCandidate()
    }

    func testStorageInventoryConfirmBecomesEnabled() {
        openEligibleStorageInventory()
        requireInitialStorageEvidence()
        selectStorageCandidate()
        assertEnabled("playstead.storage.reclaim")
    }

    func testStorageInventoryActionsPassLiveAudit() throws {
        openEligibleStorageInventory()
        requireInitialStorageEvidence()
        selectStorageCandidate()
        try harness.audit(.action, rootIdentifier: "playstead.surface.storage")
    }

    func testStorageInventoryConfirmMutationRemovesOnlyEligibleCopy() {
        openEligibleStorageInventory()
        requireInitialStorageEvidence()
        selectStorageCandidate()
        activateStorageReclaimAndVerifyMutation()
    }

    func testStorageInventoryPostMutationPreservesCanonicalRows() {
        openEligibleStorageInventory()
        requireInitialStorageEvidence()
        selectStorageCandidate()
        activateStorageReclaimAndVerifyMutation()
        dismissStorageAndAssertCanonicalRows()
    }

    func testStorageInventoryProtectsPinnedCopy() {
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

    private func openReclaimPrompt() {
        navigateToQuotaFixtureList()
        activateSelectedDownloadByKeyboard()

        let reclaimRoot = harness.element("playstead.surface.reclaim")
        XCTAssertTrue(reclaimRoot.waitForExistence(timeout: 5))
    }

    private func navigateToQuotaFixtureList() {
        launchStorageProfile(.quotaBlockReclaim)
        harness.traverseExactFocusSequence(
            [
                "playstead.control.show-cards",
                "playstead.control.show-list",
                "playstead.control.open-readiness"
            ],
            activate: "playstead.control.show-list"
        )
    }

    private func requireInitialReclaimEvidence() {
        harness.require([
            "playstead.reclaim.shortfall",
            "playstead.reclaim.selection"
        ])
        assertValue("playstead.reclaim.shortfall", equals: "48")
        assertValue("playstead.reclaim.selection", equals: "count=0;bytes=0")
    }

    private func selectReclaimCandidate() {
        harness.require(["playstead.reclaim.candidate.0.toggle"])
        harness.focusContainedAction(
            "playstead.reclaim.candidate.0.toggle",
            rootIdentifier: "playstead.surface.reclaim"
        )
        harness.element("playstead.reclaim.candidate.0.toggle", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.reclaim.selection", equals: "count=1;bytes=32")
        assertValue("playstead.reclaim.candidate.0", equals: "bytes=32;selected=true")
    }

    private func activateReclaimAndVerifyMutation() {
        assertEnabled("playstead.reclaim.confirm")
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
        waitForValue("playstead.reclaim.shortfall", equals: "16")
        waitForValue("playstead.reclaim.selection", equals: "count=0;bytes=0")
        XCTAssertEqual(elements("playstead.reclaim.candidate").count, 0)
        harness.validateSemanticTargets([.init("playstead.reclaim.cancel", type: .button)])
    }

    private func dismissReclaimAndAssertCanonicalRows() {
        let reclaimRoot = harness.element("playstead.surface.reclaim")
        harness.focusContainedAction(
            "playstead.reclaim.cancel",
            rootIdentifier: "playstead.surface.reclaim"
        )
        harness.element("playstead.reclaim.cancel", type: .button)
            .typeKey(.space, modifierFlags: [])
        XCTAssertFalse(reclaimRoot.waitForExistence(timeout: 2))
        assertCanonicalRow(assetID: quotaReclaimAssetID, title: "Synthetic Reclaim Candidate")
        assertCanonicalRow(assetID: quotaDownloadAssetID, title: "Synthetic Quota Download")
    }

    private func openEligibleStorageInventory() {
        launchStorageProfile(.quotaBlockReclaim)
        openSurface(
            control: "playstead.control.open-storage",
            root: "playstead.surface.storage"
        )
    }

    private func requireInitialStorageEvidence() {
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
        XCTAssertEqual(elements("playstead.storage.candidate").count, 1)
        assertValue("playstead.storage.candidate.0", equals: "bytes=32;selected=false")
    }

    private func selectStorageCandidate() {
        harness.focusContainedAction(
            "playstead.storage.candidate.0.toggle",
            rootIdentifier: "playstead.surface.storage"
        )
        harness.element("playstead.storage.candidate.0.toggle", type: .button)
            .typeKey(.space, modifierFlags: [])
        waitForValue("playstead.storage.selection", equals: "count=1;bytes=32")
        assertValue("playstead.storage.candidate.0", equals: "bytes=32;selected=true")
    }

    private func activateStorageReclaimAndVerifyMutation() {
        assertEnabled("playstead.storage.reclaim")
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
    }

    private func dismissStorageAndAssertCanonicalRows() {
        dismissSheet(root: "playstead.surface.storage")
        // Storage opens from the default Cards layout, unlike the reclaim
        // prompt journey that starts in List. Reveal the same production
        // GameRow identities without relaunching or reseeding; the mutation
        // proof above therefore remains the state being inspected.
        harness.element("playstead.control.show-list", type: .button).click()
        XCTAssertTrue(harness.element("playstead.surface.game-list").waitForExistence(timeout: 5))
        assertCanonicalRow(assetID: quotaReclaimAssetID, title: "Synthetic Reclaim Candidate")
        assertCanonicalRow(assetID: quotaDownloadAssetID, title: "Synthetic Quota Download")
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

    private func waitForUniqueDownloadAction() -> XCUIElement {
        let downloads = harness.app.buttons.matching(
            NSPredicate(format: "label == %@", "Download")
        )
        let exactlyOne = NSPredicate { _, _ in downloads.count == 1 }
        let expectation = XCTNSPredicateExpectation(predicate: exactlyOne, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "quota fixture did not settle to exactly one Download action"
        )
        XCTAssertEqual(downloads.count, 1)
        let action = downloads.firstMatch
        let exactIdentity = harness.element(quotaDownloadAction, type: .button)
        XCTAssertTrue(exactIdentity.waitForExistence(timeout: 5))
        XCTAssertEqual(exactIdentity.label, "Download")
        XCTAssertEqual(
            action.frame,
            exactIdentity.frame,
            "the unique actionable Download must occupy the exact quota asset's AX frame"
        )
        return action
    }

    private func selectQuotaDownloadByKeyboard() {
        _ = waitForUniqueDownloadAction()
        let list = harness.element("playstead.surface.game-list")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(
            list.value(forKey: "hasKeyboardFocus") as? Bool == true,
            "activating List must transfer keyboard focus to its production selection model"
        )

        let selection = harness.element("playstead.library.list-selection")
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            let currentSelection = selection.value as? String
            if currentSelection == quotaDownloadAssetID { break }
            list.typeKey(.downArrow, modifierFlags: [])
        }
        let settledSelection = selection.value as? String
        XCTAssertEqual(settledSelection, quotaDownloadAssetID)
        XCTAssertTrue(list.value(forKey: "hasKeyboardFocus") as? Bool == true)

        let command = harness.element("playstead.control.download-selected", type: .button)
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        XCTAssertTrue(command.isEnabled)
    }

    private func activateSelectedDownloadByKeyboard() {
        selectQuotaDownloadByKeyboard()
        harness.app.typeKey("d", modifierFlags: [.command])
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

    private func assertEnabled(_ identifier: String) {
        let action = harness.element(identifier, type: .button)
        XCTAssertTrue(action.waitForExistence(timeout: 5), "missing action: \(identifier)")
        XCTAssertTrue(action.isEnabled, "action is disabled: \(identifier)")
    }

    private func assertCanonicalRow(assetID: String, title: String) {
        let row = harness.element("playstead.game.\(assetID).summary")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "canonical row missing: \(title)")
        XCTAssertTrue(row.label.hasPrefix(title), "canonical row label drifted: \(title)")
    }

    private func waitForValue(_ identifier: String, equals expected: String) {
        let element = harness.element(identifier)
        let settled = NSPredicate { _, _ in element.value as? String == expected }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        XCTAssertEqual(element.value as? String, expected)
    }
}
