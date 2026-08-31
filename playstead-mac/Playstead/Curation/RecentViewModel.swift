import Foundation

/// Recent: recently played games, listed from the local mirror. Neither
/// Recent nor Continue is a stored rule set the user edits — both are
/// computed views over `curation_recent` (D-10).
@Observable
final class RecentViewModel {
    private let curationStore: CurationStore
    private let sessionRecorder: PlaySessionRecorder?

    private(set) var items: [CurationRecentRow] = []

    /// Cached, refresh()-driven view of `sessionRecorder`'s pending/
    /// delivered play sessions — kept here (rather than queried directly
    /// from `RecentShelfView.body`) so the underlying SQLite read runs
    /// once per actual data change instead of on every SwiftUI
    /// re-render, matching every other shelf's view-model-owned caching.
    private(set) var sessionListings: [PlaySessionListing] = []

    init(curationStore: CurationStore, sessionRecorder: PlaySessionRecorder? = nil) {
        self.curationStore = curationStore
        self.sessionRecorder = sessionRecorder
        refresh()
    }

    func refresh() {
        items = curationStore.fetchRecent()
        sessionListings = sessionRecorder?.listings() ?? []
    }

    @discardableResult
    func deleteSession(_ sessionID: String) -> Bool {
        guard let sessionRecorder else { return false }
        let deleted = sessionRecorder.delete(sessionID)
        if deleted { refresh() }
        return deleted
    }

    var isEmpty: Bool { items.isEmpty }
}
