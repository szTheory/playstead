import Foundation

/// Navigation surfaces whose content is not a flat list of games.
struct LibraryNavigationContext: Equatable {
    enum Surface: Equatable {
        case games
        case collections
    }

    let sidebarCount: Int
    let contentCount: Int
    let contentColumnCount: Int
    let filterCount: Int
    let surface: Surface
    let collectionCount: Int
    let collectionMemberCount: Int
    let hasSelectedCollection: Bool
}

/// Directional and semantic actions shared by GameController and keyboard
/// arrow handling in the library shell.
enum LibraryNavigationCommand: Equatable {
    case up
    case down
    case left
    case right
    case confirm
    case back
    case previousSection
    case nextSection
    case contextAction
}

/// Observable effects are indexes into the current canonical targets.
/// The shell resolves them to stable destination, filter, collection, or
/// game IDs and renders the visible focus treatment.
enum LibraryNavigationEffect: Equatable {
    case focusSidebar(index: Int)
    case focusFilter(index: Int)
    case focusCollection(index: Int)
    case focusContent(index: Int)
    case focusCollectionMember(index: Int)
    case selectCollection(index: Int)
    case toggleFilter(index: Int)
    case activateContent(index: Int)
    case openContextAction(index: Int)
}

/// Small deterministic transition model. It owns navigation region and
/// selection indexes, while the SwiftUI shell resolves indexes to stable
/// IDs. Collections are a three-level path: sidebar, collection list, then
/// that collection's members. Library filters sit immediately above the
/// result list and remain reachable without text entry.
struct ControllerNavigationDispatcher: Equatable {
    enum Region: Equatable {
        case sidebar
        case filters
        case content
        case collections
        case collectionMembers
    }

    private(set) var region: Region = .sidebar
    private(set) var sidebarIndex = 0
    private(set) var filterIndex = 0
    private(set) var contentIndex = 0
    private(set) var collectionIndex = 0
    private(set) var collectionMemberIndex = 0
    private var heldInputs: Set<String> = []

    mutating func receive(
        inputName: String,
        active: Bool,
        context: LibraryNavigationContext
    ) -> LibraryNavigationEffect? {
        guard Self.inputNames.contains(inputName) else { return nil }
        if active {
            guard heldInputs.insert(inputName).inserted else { return nil }
            guard let command = Self.command(for: inputName) else { return nil }
            return transition(command, context: context)
        }
        heldInputs.remove(inputName)
        return nil
    }

    mutating func move(
        _ command: LibraryNavigationCommand,
        context: LibraryNavigationContext
    ) -> LibraryNavigationEffect? {
        transition(command, context: context)
    }

    mutating func synchronizeSidebar(index: Int) {
        sidebarIndex = max(0, index)
        region = .sidebar
    }

    mutating func synchronizeFilters(index: Int) {
        filterIndex = max(0, index)
        region = .filters
    }

    mutating func synchronizeContent(index: Int) {
        contentIndex = max(0, index)
        region = .content
    }

    mutating func synchronizeCollections(index: Int) {
        collectionIndex = max(0, index)
        region = .collections
    }

    mutating func synchronizeCollectionMembers(index: Int) {
        collectionMemberIndex = max(0, index)
        region = .collectionMembers
    }

    private mutating func transition(
        _ command: LibraryNavigationCommand,
        context: LibraryNavigationContext
    ) -> LibraryNavigationEffect? {
        switch command {
        case .up:
            switch region {
            case .sidebar:
                sidebarIndex = max(0, sidebarIndex - 1)
                return .focusSidebar(index: sidebarIndex)
            case .filters:
                return returnToSidebar()
            case .content:
                let columns = max(1, context.contentColumnCount)
                if contentIndex >= columns {
                    contentIndex -= columns
                    return .focusContent(index: contentIndex)
                }
                guard context.filterCount > 0 else { return nil }
                filterIndex = min(filterIndex, context.filterCount - 1)
                region = .filters
                return .focusFilter(index: filterIndex)
            case .collections:
                guard context.collectionCount > 0 else { return nil }
                collectionIndex = max(0, collectionIndex - 1)
                return .focusCollection(index: collectionIndex)
            case .collectionMembers:
                guard context.collectionMemberCount > 0 else { return nil }
                collectionMemberIndex = max(0, collectionMemberIndex - 1)
                return .focusCollectionMember(index: collectionMemberIndex)
            }
        case .down:
            switch region {
            case .sidebar:
                sidebarIndex = min(max(0, context.sidebarCount - 1), sidebarIndex + 1)
                return .focusSidebar(index: sidebarIndex)
            case .filters:
                guard context.contentCount > 0 else { return nil }
                region = .content
                contentIndex = min(contentIndex, context.contentCount - 1)
                return .focusContent(index: contentIndex)
            case .content:
                guard context.contentCount > 0 else { return nil }
                let nextIndex = contentIndex + max(1, context.contentColumnCount)
                guard nextIndex < context.contentCount else { return nil }
                contentIndex = nextIndex
                return .focusContent(index: contentIndex)
            case .collections:
                guard context.collectionCount > 0 else { return nil }
                collectionIndex = min(context.collectionCount - 1, collectionIndex + 1)
                return .focusCollection(index: collectionIndex)
            case .collectionMembers:
                guard context.collectionMemberCount > 0 else { return nil }
                collectionMemberIndex = min(context.collectionMemberCount - 1, collectionMemberIndex + 1)
                return .focusCollectionMember(index: collectionMemberIndex)
            }
        case .right:
            switch region {
            case .sidebar:
                return enterSelectedDestination(context: context)
            case .filters:
                guard context.filterCount > 0 else { return nil }
                if filterIndex + 1 < context.filterCount {
                    filterIndex += 1
                    return .focusFilter(index: filterIndex)
                }
                guard context.contentCount > 0 else { return nil }
                region = .content
                contentIndex = min(contentIndex, context.contentCount - 1)
                return .focusContent(index: contentIndex)
            case .content:
                let columns = max(1, context.contentColumnCount)
                guard columns > 1, contentIndex % columns + 1 < columns,
                      contentIndex + 1 < context.contentCount else { return nil }
                contentIndex += 1
                return .focusContent(index: contentIndex)
            case .collections:
                guard context.hasSelectedCollection, context.collectionMemberCount > 0 else { return nil }
                region = .collectionMembers
                collectionMemberIndex = 0
                return .focusCollectionMember(index: collectionMemberIndex)
            case .collectionMembers:
                return nil
            }
        case .left, .back:
            switch region {
            case .sidebar:
                return nil
            case .filters:
                if command == .left, filterIndex > 0 {
                    filterIndex -= 1
                    return .focusFilter(index: filterIndex)
                }
                return returnToSidebar()
            case .content:
                let columns = max(1, context.contentColumnCount)
                if columns > 1, contentIndex % columns > 0 {
                    contentIndex -= 1
                    return .focusContent(index: contentIndex)
                }
                return returnToSidebar()
            case .collections:
                return returnToSidebar()
            case .collectionMembers:
                region = .collections
                return .focusCollection(index: collectionIndex)
            }
        case .confirm:
            switch region {
            case .sidebar:
                return enterSelectedDestination(context: context)
            case .filters:
                guard context.filterCount > 0 else { return nil }
                return .toggleFilter(index: min(filterIndex, context.filterCount - 1))
            case .content:
                guard context.contentCount > 0 else { return nil }
                return .activateContent(index: min(contentIndex, context.contentCount - 1))
            case .collections:
                guard context.collectionCount > 0 else { return nil }
                return .selectCollection(index: min(collectionIndex, context.collectionCount - 1))
            case .collectionMembers:
                guard context.collectionMemberCount > 0 else { return nil }
                return .activateContent(index: min(collectionMemberIndex, context.collectionMemberCount - 1))
            }
        case .previousSection, .nextSection:
            guard context.sidebarCount > 0 else { return nil }
            let delta = command == .previousSection ? -1 : 1
            sidebarIndex = (sidebarIndex + delta + context.sidebarCount) % context.sidebarCount
            region = .sidebar
            return .focusSidebar(index: sidebarIndex)
        case .contextAction:
            switch region {
            case .content:
                guard context.contentCount > 0 else { return nil }
                return .openContextAction(index: min(contentIndex, context.contentCount - 1))
            case .collectionMembers:
                guard context.collectionMemberCount > 0 else { return nil }
                return .openContextAction(index: min(collectionMemberIndex, context.collectionMemberCount - 1))
            case .sidebar, .filters, .collections:
                return nil
            }
        }
    }

    private mutating func enterSelectedDestination(context: LibraryNavigationContext) -> LibraryNavigationEffect? {
        switch context.surface {
        case .games:
            if context.contentCount > 0 {
                region = .content
                contentIndex = 0
                return .focusContent(index: contentIndex)
            }
            if context.filterCount > 0 {
                region = .filters
                filterIndex = min(filterIndex, context.filterCount - 1)
                return .focusFilter(index: filterIndex)
            }
            return nil
        case .collections:
            guard context.collectionCount > 0 else { return nil }
            region = .collections
            collectionIndex = min(collectionIndex, context.collectionCount - 1)
            return .focusCollection(index: collectionIndex)
        }
    }

    private mutating func returnToSidebar() -> LibraryNavigationEffect {
        region = .sidebar
        return .focusSidebar(index: sidebarIndex)
    }

    private static let inputNames: Set<String> = [
        "dpadUp", "dpadDown", "dpadLeft", "dpadRight", "buttonA", "buttonB",
        "leftShoulder", "rightShoulder", "buttonMenu", "buttonOptions"
    ]

    private static func command(for inputName: String) -> LibraryNavigationCommand? {
        switch inputName {
        case "dpadUp": .up
        case "dpadDown": .down
        case "dpadLeft": .left
        case "dpadRight": .right
        case "buttonA": .confirm
        case "buttonB": .back
        case "leftShoulder": .previousSection
        case "rightShoulder": .nextSection
        case "buttonMenu", "buttonOptions": .contextAction
        default: nil
        }
    }
}
