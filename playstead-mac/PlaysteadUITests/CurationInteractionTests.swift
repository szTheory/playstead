import XCTest

@MainActor
final class CurationInteractionTests: XCTestCase {
    private var harness: UITestHarness?

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
    }

    func testCurationProfileBootstrapsLibrarySurface() throws {
        _ = launchPersistentCurationHarness()
    }

    func testSidebarExposesAllFiveCurationDestinations() throws {
        let harness = launchPersistentCurationHarness()
        for label in ["Continue", "Favorites", "Collections", "Queue", "Recent"] {
            XCTAssertTrue(harness.app.staticTexts[label].waitForExistence(timeout: 5), "sidebar entry missing: \(label)")
        }
    }

    func testContinueShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Continue", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.continue").waitForExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Play something, and pick up where you left off here."].waitForExistence(timeout: 5))
        assertSyntheticGamesVisible(0, in: harness)
    }

    func testFavoritesShelfRootExists() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Favorites", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.favorites").waitForExistence(timeout: 5))
    }

    func testFavoritesShelfRendersExactSeededCard() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Favorites", in: harness)
        let cards = harness.app.descendants(matching: .any).matching(identifier: "library.card")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.element(boundBy: 0).label, "Synthetic Game 1, Unidentified")
    }

    func testCollectionsShelfRootExists() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Collections", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.collections").waitForExistence(timeout: 5))
    }

    func testCollectionsShelfRendersExactSeededRoute() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Collections", in: harness)
        let rows = harness.app.buttons.matching(identifier: collectionRowID)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.element(boundBy: 0).label, "Synthetic Collection")
    }

    func testQueueShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Queue", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.play-queue").waitForExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Add a game to your queue to keep it in mind."].waitForExistence(timeout: 5))
        assertSyntheticGamesVisible(0, in: harness)
    }

    func testRecentShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Recent", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.recent").waitForExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Play a game to see it here."].waitForExistence(timeout: 5))
        assertSyntheticGamesVisible(0, in: harness)
    }

    func testCollectionDetailOpensExactSeededState() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertExactCollectionOrder(initialOrder, in: harness)
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)
    }

    func testCollectionDragTargetsOwnDistinctListCells() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let cells = (1...3).map { listCell(containing: rowID($0), in: harness) }
        for cell in cells { XCTAssertTrue(cell.waitForExistence(timeout: 5)) }
        XCTAssertEqual(Set(cells.map { $0.frame.minY }).count, 3)
    }

    func testCollectionMoveUpActionIsEnabledAndOwned() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let action = harness.element(moveID(memberID(2), direction: "up"), type: .button)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.label, "Move Synthetic Game 2 up")
    }

    func testCollectionMoveUpClickProducesOneEffect() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let action = harness.element(moveID(memberID(2), direction: "up"), type: .button)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.click()
        let order = [memberID(2), memberID(1), memberID(3)]
        assertEvidence(order: order, outboxCount: 1, in: harness)
        assertExactCollectionOrder(order, in: harness)
    }

    func testDragReorderProducesOneEffect() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)

        let draggedOrder = assertInitialOrderAndPerformDrag(in: harness)
        assertEvidence(order: draggedOrder, outboxCount: 1, in: harness)
        assertExactCollectionOrder(draggedOrder, in: harness)
    }

    func testDragReorderSurvivesRelaunch() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)

        let draggedOrder = assertInitialOrderAndPerformDrag(in: harness)
        assertEvidence(order: draggedOrder, outboxCount: 1, in: harness)
        assertExactCollectionOrder(draggedOrder, in: harness)

        harness.relaunch(settledAt: "playstead.surface.library")
        openSyntheticCollection(in: harness)
        assertEvidence(order: draggedOrder, outboxCount: 1, in: harness)
        assertExactCollectionOrder(draggedOrder, in: harness)
    }

    func testKeyboardReorderProducesOneEffectAndRetainsFocus() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        _ = performInitialKeyboardMove(in: harness)
    }

    func testKeyboardReorderSurvivesRelaunch() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let result = performInitialKeyboardMove(in: harness)

        harness.relaunch(settledAt: "playstead.surface.library")
        openSyntheticCollection(in: harness)
        assertEvidence(order: result.order, outboxCount: 1, in: harness)
        assertExactCollectionOrder(result.order, in: harness)
    }

    func testKeyboardReorderRetainsFocusAndSurvivesRelaunch() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)

        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertExactCollectionOrder(initialOrder, in: harness)
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)

        let draggedOrder = performExactDrag(in: harness)
        assertEvidence(order: draggedOrder, outboxCount: 1, in: harness)
        assertExactCollectionOrder(draggedOrder, in: harness)

        harness.relaunch(settledAt: "playstead.surface.library")
        openSyntheticCollection(in: harness)
        assertEvidence(order: draggedOrder, outboxCount: 1, in: harness)
        assertExactCollectionOrder(draggedOrder, in: harness)

        let firstMoveUp = harness.element(moveID(memberID(3), direction: "up"), type: .button)
        let lastMoveDown = harness.element(moveID(memberID(2), direction: "down"), type: .button)
        assertEnabled(false, element: firstMoveUp)
        assertEnabled(false, element: lastMoveDown)

        let keyboardMove = moveID(memberID(2), direction: "up")
        harness.focusContainedAction(
            keyboardMove,
            rootIdentifier: "playstead.surface.collection-detail"
        )
        let keyboardMoveButton = harness.element(keyboardMove, type: .button)
        keyboardMoveButton.typeKey(.space, modifierFlags: [])

        let keyboardOrder = [memberID(3), memberID(2), memberID(1)]
        assertEvidence(order: keyboardOrder, outboxCount: 2, in: harness)
        assertExactCollectionOrder(keyboardOrder, in: harness)
        waitForKeyboardFocus(keyboardMoveButton)
        assertEnabled(
            false,
            element: harness.element(moveID(memberID(3), direction: "up"), type: .button)
        )
        assertEnabled(
            false,
            element: harness.element(moveID(memberID(1), direction: "down"), type: .button)
        )

        harness.relaunch(settledAt: "playstead.surface.library")
        openSyntheticCollection(in: harness)
        assertEvidence(order: keyboardOrder, outboxCount: 2, in: harness)
        assertExactCollectionOrder(keyboardOrder, in: harness)
    }

    private func launchPersistentCurationHarness() -> UITestHarness {
        let harness = UITestHarness(profile: .populatedCurationReorder, persistentSession: true)
        self.harness = harness
        harness.launch(settledAt: "playstead.surface.library")
        return harness
    }

    private func performExactDrag(in harness: UITestHarness) -> [String] {
        // The identified HStack owns semantic row evidence; its enclosing
        // List cell owns SwiftUI's onMove drag interaction.
        let first = listCell(containing: rowID(1), in: harness)
        let third = listCell(containing: rowID(3), in: harness)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(third.waitForExistence(timeout: 5))

        // Last-to-first has one unambiguous destination boundary. Dropping the
        // first row on the last row's center can resolve on either side of it.
        // This is a hosted macOS UI test: use the mouse-owned click-drag API.
        // The touch-style press-drag call can complete without dispatching the
        // List's production onMove command on macOS.
        third.click(
            forDuration: 1,
            thenDragTo: first,
            withVelocity: XCUIGestureVelocity.slow,
            thenHoldForDuration: 1
        )
        return [memberID(3), memberID(1), memberID(2)]
    }

    private func listCell(containing identifier: String, in harness: UITestHarness) -> XCUIElement {
        harness.app.cells.containing(.any, identifier: identifier).element(boundBy: 0)
    }

    private func assertInitialOrderAndPerformDrag(in harness: UITestHarness) -> [String] {
        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertExactCollectionOrder(initialOrder, in: harness)
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)
        return performExactDrag(in: harness)
    }

    private func performInitialKeyboardMove(in harness: UITestHarness) -> (order: [String], button: XCUIElement) {
        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertExactCollectionOrder(initialOrder, in: harness)
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)
        assertEnabled(false, element: harness.element(moveID(memberID(1), direction: "up"), type: .button))
        assertEnabled(false, element: harness.element(moveID(memberID(3), direction: "down"), type: .button))

        let keyboardMove = moveID(memberID(2), direction: "up")
        // focusContainedAction performs only the focus transition. Space is
        // sent exactly once, after the helper returns.
        harness.focusContainedAction(keyboardMove, rootIdentifier: "playstead.surface.collection-detail")
        let button = harness.element(keyboardMove, type: .button)
        button.typeKey(.space, modifierFlags: [])

        let order = [memberID(2), memberID(1), memberID(3)]
        assertEvidence(order: order, outboxCount: 1, in: harness)
        assertExactCollectionOrder(order, in: harness)
        waitForKeyboardFocus(button)
        assertEnabled(false, element: harness.element(moveID(memberID(2), direction: "up"), type: .button))
        assertEnabled(false, element: harness.element(moveID(memberID(3), direction: "down"), type: .button))
        return (order, button)
    }

    private func assertSyntheticGamesVisible(_ expected: Int, in harness: UITestHarness) {
        let games = harness.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic Game "))
        XCTAssertEqual(games.count, expected)
    }

    private func openSyntheticCollection(in harness: UITestHarness) {
        selectSidebar("Collections", in: harness)
        let collection = harness.element(collectionRowID, type: .button)
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        collection.click()
        XCTAssertTrue(harness.element("playstead.surface.collection-detail").waitForExistence(timeout: 5))
    }

    private func selectSidebar(_ label: String, in harness: UITestHarness) {
        let entry = harness.app.staticTexts[label]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "sidebar entry missing: \(label)")
        entry.click()
    }

    private func assertExactCollectionOrder(_ expected: [String], in harness: UITestHarness) {
        let allRows = harness.app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@",
                "playstead.curation.collection-member.",
                ".move-"
            )
        )
        XCTAssertEqual(allRows.count, 3)
        let rows = expected.map { harness.element("playstead.curation.collection-member.\($0)") }
        for row in rows { XCTAssertTrue(row.waitForExistence(timeout: 5)) }
        let visualOrder = rows.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier)
        XCTAssertEqual(visualOrder, expected.map { "playstead.curation.collection-member.\($0)" })
        for (row, memberID) in zip(rows, expected) {
            XCTAssertEqual(row.label, "Synthetic Game \(Int(memberID.suffix(1))!)")
        }
    }

    private func assertEvidence(order: [String], outboxCount: Int, in harness: UITestHarness) {
        waitForValue(
            harness.element("playstead.test.curation.evidence"),
            equals: evidence(order: order, outboxCount: outboxCount)
        )
    }

    private func waitForValue(_ element: XCUIElement, equals expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func waitForKeyboardFocus(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func assertEnabled(_ expected: Bool, element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: expected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func evidence(order: [String], outboxCount: Int) -> String {
        "order=\(order.joined(separator: ","));outbox=\(outboxCount);catalogue=\(Self.catalogueFingerprint)"
    }

    private func rowID(_ ordinal: Int) -> String {
        "playstead.curation.collection-member.\(memberID(ordinal))"
    }

    private func moveID(_ memberID: String, direction: String) -> String {
        "playstead.curation.collection-member.\(memberID).move-\(direction)"
    }

    private func memberID(_ ordinal: Int) -> String {
        String(format: "00000000-0000-7000-8000-00000000020%d", ordinal)
    }

    private let collectionRowID = "playstead.curation.collection.00000000-0000-7000-8000-000000000200"

    private static let catalogueFingerprint = [
        "72cd6e8422c407fb6d098690f1130b7ded7ec2f7f5e1d30bd9d521f015363793",
        "75877bb41d393b5fb8455ce60ecd8dda001d06316496b14dfa7f895656eeca4a",
        "648aa5c579fb30f38af744d97d6ec840c7a91277a499a0d780f3e7314eca090b"
    ].sorted().joined(separator: ",")
}
