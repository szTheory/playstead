import Foundation

/// Recent: recently played games, listed from the local mirror. Neither
/// Recent nor Continue is a stored rule set the user edits — both are
/// computed views over `curation_recent` (D-10).
@Observable
final class RecentViewModel {
    private let curationStore: CurationStore

    private(set) var items: [CurationRecentRow] = []

    init(curationStore: CurationStore) {
        self.curationStore = curationStore
        refresh()
    }

    func refresh() {
        items = curationStore.fetchRecent()
    }

    var isEmpty: Bool { items.isEmpty }
}
