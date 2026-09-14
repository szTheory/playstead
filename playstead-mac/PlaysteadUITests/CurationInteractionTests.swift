import XCTest

@MainActor
final class CurationInteractionTests: XCTestCase {
    private var harness: UITestHarness?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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
            XCTAssertTrue(harness.app.staticTexts[label].awaitExistence(timeout: 5), "sidebar entry missing: \(label)")
        }
    }

    func testContinueShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Continue", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.continue").awaitExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Play something, and pick up where you left off here."].awaitExistence(timeout: 5))
        assertSyntheticGamesVisible(0, in: harness)
    }

    func testFavoritesShelfRootExists() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Favorites", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.favorites").awaitExistence(timeout: 5))
    }

    func testFavoritesShelfRendersExactSeededCard() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Favorites", in: harness)
        let cards = harness.app.descendants(matching: .any).matching(identifier: "library.card")
        XCTAssertEqual(cards.count, 1)
        // The shelf was constructed without its `statuses` closure, so its
        // cards carried no status rung at all and this label ended after
        // the system name (WINDOWS #72). It now composes the same three
        // facts the grid's cards do -- title, system, status sentence --
        // and the seeded fixture is uncached, so the sentence is the
        // server-only one. Asserted as an exact whole, matching this
        // suite's posture, rather than loosened to a prefix.
        XCTAssertEqual(
            cards.element(boundBy: 0).readableText,
            "Synthetic Game 1, Unidentified, Synthetic Game 1 is on your server. Choose Download to play it offline."
        )
    }

    func testCollectionsShelfRootExists() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Collections", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.collections").awaitExistence(timeout: 5))
    }

    func testCollectionsShelfRendersExactSeededRoute() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Collections", in: harness)
        let rows = harness.app.buttons.matching(identifier: collectionRowID)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.element(boundBy: 0).readableText, "Synthetic Collection")
    }

    func testQueueShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Queue", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.play-queue").awaitExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Add a game to your queue to keep it in mind."].awaitExistence(timeout: 5))
        assertSyntheticGamesVisible(0, in: harness)
    }

    func testRecentShelfRendersHonestEmptyFixture() throws {
        let harness = launchPersistentCurationHarness()
        selectSidebar("Recent", in: harness)
        XCTAssertTrue(harness.element("playstead.surface.shelf.recent").awaitExistence(timeout: 5))
        XCTAssertTrue(harness.app.staticTexts["Play a game to see it here."].awaitExistence(timeout: 5))
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
        for cell in cells { XCTAssertTrue(cell.awaitExistence(timeout: 5)) }
        XCTAssertEqual(Set(cells.map { $0.frame.minY }).count, 3)
    }

    func testCollectionMoveUpActionIsEnabledAndOwned() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let action = harness.element(moveID(memberID(2), direction: "up"), type: .button)
        XCTAssertTrue(action.awaitExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.readableText, "Move Synthetic Game 2 up")
    }

    func testCollectionMoveUpClickProducesOneEffect() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)
        assertExactCollectionOrder(initialOrder, in: harness)
        let action = harness.element(moveID(memberID(2), direction: "up"), type: .button)
        XCTAssertTrue(action.awaitExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        XCTAssertTrue(action.isHittable)
        action.clickWhenHittable()
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

    func testKeyboardSelectionTargetReceivesFocus() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        _ = selectCollectionMemberByKeyboard(memberID(3), in: harness)
    }

    func testKeyboardCommandProducesOneEffect() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        _ = selectCollectionMemberByKeyboard(memberID(3), in: harness)
        activateSelectedMoveUp(in: harness)
        assertEvidence(order: [memberID(1), memberID(3), memberID(2)], outboxCount: 1, in: harness)
    }

    func testKeyboardCommandRetainsSelectionAndFocus() throws {
        let harness = launchPersistentCurationHarness()
        openSyntheticCollection(in: harness)
        let list = selectCollectionMemberByKeyboard(memberID(3), in: harness)
        activateSelectedMoveUp(in: harness)
        assertEvidence(order: [memberID(1), memberID(3), memberID(2)], outboxCount: 1, in: harness)
        assertSelection(memberID(3), in: harness)
        waitForKeyboardFocus(list, stage: "list-focus-lost-after-settlement")
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

        let memberList = selectCollectionMemberByKeyboard(memberID(2), in: harness)
        activateSelectedMoveUp(in: harness)

        let keyboardOrder = [memberID(3), memberID(2), memberID(1)]
        assertEvidence(order: keyboardOrder, outboxCount: 2, in: harness)
        assertExactCollectionOrder(keyboardOrder, in: harness)
        assertSelection(memberID(2), in: harness)
        waitForKeyboardFocus(memberList, stage: "list-focus-lost-after-settlement")
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

    // MARK: - The list layout's sort control (WINDOWS #79)

    /// `LibrarySortOption` and `GameListView.sorted(_:by:)` existed and were
    /// tested for the whole of phase 03 while nothing in the shipped app
    /// could reach either: the list layout renders `GameRowView`, and no
    /// sort control was offered anywhere. This asserts the control exists
    /// where a user can actually press it, that pressing it takes effect,
    /// and that the rows come out in the order it names.
    func testListLayoutOffersAWorkingSortControl() {
        let harness = launchPersistentCurationHarness()

        harness.element("playstead.control.show-list", type: .button).clickWhenHittable()

        let byTitle = harness.element("playstead.control.sort-title", type: .button)
        let bySystem = harness.element("playstead.control.sort-system", type: .button)
        XCTAssertTrue(byTitle.awaitExistence(timeout: 5), "the list layout offers no way to sort")
        XCTAssertTrue(bySystem.exists)
        XCTAssertEqual(byTitle.value as? String, "selected", "title is the default ordering")
        XCTAssertEqual(bySystem.value as? String, "not selected")

        // Pressing it must actually change the state the list body reads --
        // a control that renders and does nothing is the defect one level
        // up from having no control at all.
        bySystem.clickWhenHittable()
        XCTAssertEqual(bySystem.value as? String, "selected")
        XCTAssertEqual(byTitle.value as? String, "not selected")

        // And the rows are ordered. The seeded fixture is three games whose
        // titles sort the same way their ids do, so this pins the ordering
        // that is observable here rather than claiming more than the
        // fixture can show; `LibrarySortTests` covers the orderings
        // themselves against inputs built for the purpose.
        byTitle.clickWhenHittable()
        let titles = (1...3).map { "Synthetic Game \($0)" }
        let rendered = harness.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "playstead.game.", ".summary"))
            .allElementsBoundByIndex
            .map(\.readableText)
        for title in titles {
            XCTAssertTrue(
                rendered.contains(where: { $0.hasPrefix(title) }),
                "the sorted list dropped \(title): \(rendered)"
            )
        }
        let positions = titles.compactMap { title in rendered.firstIndex(where: { $0.hasPrefix(title) }) }
        XCTAssertEqual(positions, positions.sorted(), "rows are not in title order: \(rendered)")
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
        XCTAssertTrue(first.awaitExistence(timeout: 5))
        XCTAssertTrue(third.awaitExistence(timeout: 5))

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

    private func performInitialKeyboardMove(in harness: UITestHarness) -> (order: [String], focusOwner: XCUIElement) {
        let initialOrder = [memberID(1), memberID(2), memberID(3)]
        assertExactCollectionOrder(initialOrder, in: harness)
        assertEvidence(order: initialOrder, outboxCount: 0, in: harness)
        assertEnabled(false, element: harness.element(moveID(memberID(1), direction: "up"), type: .button))
        assertEnabled(false, element: harness.element(moveID(memberID(3), direction: "down"), type: .button))

        // Select the last member with ordinary List keyboard navigation, then
        // invoke the visible Move selected up command exactly once.
        let memberList = selectCollectionMemberByKeyboard(memberID(3), in: harness)
        activateSelectedMoveUp(in: harness)

        let order = [memberID(1), memberID(3), memberID(2)]
        assertEvidence(order: order, outboxCount: 1, in: harness)
        assertExactCollectionOrder(order, in: harness)
        assertSelection(memberID(3), in: harness)
        waitForKeyboardFocus(memberList, stage: "list-focus-lost-after-settlement")
        assertEnabled(
            true,
            element: harness.element("playstead.curation.collection-command.move-up", type: .button)
        )
        assertEnabled(
            true,
            element: harness.element("playstead.curation.collection-command.move-down", type: .button)
        )
        assertEnabled(false, element: harness.element(moveID(memberID(1), direction: "up"), type: .button))
        assertEnabled(false, element: harness.element(moveID(memberID(2), direction: "down"), type: .button))
        return (order, memberList)
    }

    private func assertSyntheticGamesVisible(_ expected: Int, in harness: UITestHarness) {
        let games = harness.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Synthetic Game ", "Synthetic Game "))
        XCTAssertEqual(games.count, expected)
    }

    private func openSyntheticCollection(in harness: UITestHarness) {
        selectSidebar("Collections", in: harness)
        let collection = harness.element(collectionRowID, type: .button)
        XCTAssertTrue(collection.awaitExistence(timeout: 5))
        collection.clickWhenHittable()
        XCTAssertTrue(harness.element("playstead.surface.collection-detail").awaitExistence(timeout: 5))
    }

    private func selectSidebar(_ label: String, in harness: UITestHarness) {
        let entry = harness.app.staticTexts[label]
        XCTAssertTrue(entry.awaitExistence(timeout: 5), "sidebar entry missing: \(label)")
        entry.clickWhenHittable()
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
        for row in rows { XCTAssertTrue(row.awaitExistence(timeout: 5)) }
        let visualOrder = rows.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier)
        XCTAssertEqual(visualOrder, expected.map { "playstead.curation.collection-member.\($0)" })
        for (row, memberID) in zip(rows, expected) {
            XCTAssertEqual(row.readableText, "Synthetic Game \(Int(memberID.suffix(1))!)")
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

    private func selectCollectionMemberByKeyboard(_ memberID: String, in harness: UITestHarness) -> XCUIElement {
        let list = harness.element("playstead.curation.collection-member-list")
        XCTAssertTrue(list.awaitExistence(timeout: 5), "curation-keyboard-stage=list-missing")
        waitForKeyboardFocus(list, stage: "list-focus-not-owned")

        let selection = harness.element("playstead.curation.collection-selection")
        XCTAssertTrue(selection.awaitExistence(timeout: 5), "curation-keyboard-stage=selection-missing")
        for _ in 0..<3 where selection.value as? String != memberID {
            list.typeKey(.downArrow, modifierFlags: [])
        }
        XCTAssertEqual(
            selection.value as? String,
            memberID,
            "curation-keyboard-stage=selection-target-not-reached"
        )
        waitForKeyboardFocus(list, stage: "list-focus-lost-during-selection")

        let command = harness.element("playstead.curation.collection-command.move-up", type: .button)
        XCTAssertTrue(command.awaitExistence(timeout: 5), "curation-keyboard-stage=command-missing")
        XCTAssertTrue(command.isEnabled, "curation-keyboard-stage=command-disabled")
        assertEnabled(
            false,
            element: harness.element("playstead.curation.collection-command.move-down", type: .button)
        )
        return list
    }

    private func activateSelectedMoveUp(in harness: UITestHarness) {
        harness.app.typeKey("u", modifierFlags: [.command, .option])
    }

    private func assertSelection(_ memberID: String, in harness: UITestHarness) {
        let selection = harness.element("playstead.curation.collection-selection")
        XCTAssertEqual(
            selection.value as? String,
            memberID,
            "curation-keyboard-stage=selection-lost-after-settlement"
        )
    }

    private func waitForKeyboardFocus(_ element: XCUIElement, stage: String) {
        let predicate = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "curation-keyboard-stage=\(stage)"
        )
    }

    private func assertEnabled(_ expected: Bool, element: XCUIElement) {
        XCTAssertTrue(element.awaitExistence(timeout: 5))
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
