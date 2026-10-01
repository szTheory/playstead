import XCTest
@testable import Playstead

final class ControllerNavigationTests: XCTestCase {
    func testSidebarUpDownAndRightLeftHandoffUseStableIndexes() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 4, contentCount: 2)

        XCTAssertEqual(dispatcher.move(.down, context: context), .focusSidebar(index: 1))
        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.move(.down, context: context), .focusContent(index: 1))
        XCTAssertEqual(dispatcher.move(.left, context: context), .focusSidebar(index: 1))
    }

    func testRightEntersRecentlyPlayedAtItsFirstAvailableGame() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 8, contentCount: 3)

        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.move(.confirm, context: context), .activateContent(index: 0))
    }

    func testCardGridMovementFollowsRowsAndColumnsWithoutWrapping() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 8, contentCount: 8, contentColumnCount: 3)

        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 1))
        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 2))
        XCTAssertNil(dispatcher.move(.right, context: context))
        XCTAssertEqual(dispatcher.move(.down, context: context), .focusContent(index: 5))
        XCTAssertNil(dispatcher.move(.down, context: context))
        XCTAssertEqual(dispatcher.move(.left, context: context), .focusContent(index: 4))
        XCTAssertEqual(dispatcher.move(.up, context: context), .focusContent(index: 1))
        XCTAssertEqual(dispatcher.move(.left, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.move(.left, context: context), .focusSidebar(index: 0))
    }

    func testCardGridColumnCountTracksAvailableWidth() {
        XCTAssertEqual(LibraryShellView.gridColumnCount(for: 280), 1)
        XCTAssertEqual(LibraryShellView.gridColumnCount(for: 584), 2)
        XCTAssertEqual(LibraryShellView.gridColumnCount(for: 888), 3)
        XCTAssertEqual(LibraryShellView.gridColumnCount(for: .infinity), 1)
    }

    func testCollectionsNavigateSidebarListAndMembersAsDistinctLevels() {
        var dispatcher = ControllerNavigationDispatcher()
        let collectionList = navigationContext(sidebarCount: 8, surface: .collections, collectionCount: 2)
        let selectedCollection = navigationContext(
            sidebarCount: 8, surface: .collections, collectionCount: 2,
            collectionMemberCount: 2, hasSelectedCollection: true
        )

        XCTAssertEqual(dispatcher.move(.right, context: collectionList), .focusCollection(index: 0))
        XCTAssertEqual(dispatcher.move(.down, context: collectionList), .focusCollection(index: 1))
        XCTAssertEqual(dispatcher.move(.confirm, context: collectionList), .selectCollection(index: 1))
        XCTAssertEqual(dispatcher.move(.right, context: selectedCollection), .focusCollectionMember(index: 0))
        XCTAssertEqual(dispatcher.move(.down, context: selectedCollection), .focusCollectionMember(index: 1))
        XCTAssertEqual(dispatcher.move(.back, context: selectedCollection), .focusCollection(index: 1))
        XCTAssertEqual(dispatcher.move(.back, context: collectionList), .focusSidebar(index: 0))
    }

    func testFirstGameCanMoveUpToFilterChipsAndBackIntoResults() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 8, contentCount: 3, filterCount: 4)

        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.move(.up, context: context), .focusFilter(index: 0))
        XCTAssertEqual(dispatcher.move(.right, context: context), .focusFilter(index: 1))
        XCTAssertEqual(dispatcher.move(.confirm, context: context), .toggleFilter(index: 1))
        XCTAssertEqual(dispatcher.move(.down, context: context), .focusContent(index: 0))
    }

    func testCrossAndCircleMapToConfirmAndBack() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 4, contentCount: 1)

        XCTAssertEqual(dispatcher.receive(inputName: "buttonA", active: true, context: context), .focusContent(index: 0))
        XCTAssertNil(dispatcher.receive(inputName: "buttonA", active: false, context: context))
        XCTAssertEqual(dispatcher.receive(inputName: "buttonA", active: true, context: context), .activateContent(index: 0))
        XCTAssertEqual(dispatcher.receive(inputName: "buttonB", active: true, context: context), .focusSidebar(index: 0))
    }

    func testHeldDirectionalAndContextInputsDoNotRepeatUntilReleased() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 5, contentCount: 2)

        XCTAssertEqual(dispatcher.receive(inputName: "dpadDown", active: true, context: context), .focusSidebar(index: 1))
        XCTAssertNil(dispatcher.receive(inputName: "dpadDown", active: true, context: context))
        XCTAssertNil(dispatcher.receive(inputName: "dpadDown", active: false, context: context))
        XCTAssertEqual(dispatcher.receive(inputName: "dpadDown", active: true, context: context), .focusSidebar(index: 2))

        XCTAssertEqual(dispatcher.move(.right, context: context), .focusContent(index: 0))
        XCTAssertEqual(dispatcher.receive(inputName: "buttonMenu", active: true, context: context), .openContextAction(index: 0))
        XCTAssertNil(dispatcher.receive(inputName: "buttonMenu", active: true, context: context))
        XCTAssertNil(dispatcher.receive(inputName: "buttonMenu", active: false, context: context))
        XCTAssertEqual(dispatcher.receive(inputName: "buttonMenu", active: true, context: context), .openContextAction(index: 0))
    }

    func testShouldersCycleCanonicalSidebarAndUnknownInputsAreIgnored() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 4, contentCount: 1)

        XCTAssertEqual(dispatcher.receive(inputName: "leftShoulder", active: true, context: context), .focusSidebar(index: 3))
        XCTAssertNil(dispatcher.receive(inputName: "notAControllerInput", active: true, context: context))
        XCTAssertEqual(dispatcher.receive(inputName: "rightShoulder", active: true, context: context), .focusSidebar(index: 0))
    }

    func testHiddenOrUnavailableContentNeverReceivesActivationOrContextAction() {
        var dispatcher = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 3)

        XCTAssertNil(dispatcher.move(.right, context: context))
        XCTAssertNil(dispatcher.move(.confirm, context: context))
        XCTAssertNil(dispatcher.move(.contextAction, context: context))
        XCTAssertEqual(dispatcher.move(.down, context: context), .focusSidebar(index: 1))
    }

    func testKeyboardDirectionsShareTheControllerTransitionReducer() {
        var controller = ControllerNavigationDispatcher()
        var keyboard = ControllerNavigationDispatcher()
        let context = navigationContext(sidebarCount: 4, contentCount: 3)
        let commands: [LibraryNavigationCommand] = [.down, .right, .down, .left]

        for command in commands {
            XCTAssertEqual(controller.move(command, context: context), keyboard.move(command, context: context))
        }
        XCTAssertEqual(controller, keyboard)
    }

    private func navigationContext(
        sidebarCount: Int,
        contentCount: Int = 0,
        contentColumnCount: Int = 1,
        filterCount: Int = 0,
        surface: LibraryNavigationContext.Surface = .games,
        collectionCount: Int = 0,
        collectionMemberCount: Int = 0,
        hasSelectedCollection: Bool = false
    ) -> LibraryNavigationContext {
        LibraryNavigationContext(
            sidebarCount: sidebarCount,
            contentCount: contentCount,
            contentColumnCount: contentColumnCount,
            filterCount: filterCount,
            surface: surface,
            collectionCount: collectionCount,
            collectionMemberCount: collectionMemberCount,
            hasSelectedCollection: hasSelectedCollection
        )
    }
}
