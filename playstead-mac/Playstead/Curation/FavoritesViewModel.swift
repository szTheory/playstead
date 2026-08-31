import Foundation

/// Favorites — the first curation noun built over the offline outbox
/// path (plan 03-08 task 1). Reads from `CurationStore`, the converged
/// local read model; every mutation writes through `Outbox`, applying
/// optimistically (immediately, before any network request completes)
/// so the interface never waits on the network for a favorite.
@Observable
final class FavoritesViewModel {
    private let curationStore: CurationStore
    private let outbox: Outbox

    private(set) var favorites: [CurationFavoriteRow] = []

    init(curationStore: CurationStore, outbox: Outbox) {
        self.curationStore = curationStore
        self.outbox = outbox
        refresh()
    }

    /// Re-reads favorites from the local store — called after every
    /// mutation and after a sync/journal-apply pass.
    func refresh() {
        favorites = curationStore.fetchFavorites()
    }

    var isEmpty: Bool { favorites.isEmpty }

    func isFavorited(assetSetID: String) -> Bool {
        favorites.contains { $0.assetSetID == assetSetID }
    }

    /// Favorites `assetSetID` — a no-op if already favorited locally, so
    /// repeatedly tapping an already-favorited card never enqueues a
    /// second intent.
    @discardableResult
    func addFavorite(assetSetID: String) -> Bool {
        guard !isFavorited(assetSetID: assetSetID) else { return false }
        let id = UUID().uuidString
        guard (try? outbox.enqueue(.favoriteAdd(id: id, assetSetID: assetSetID))) != nil else { return false }
        refresh()
        return true
    }

    @discardableResult
    func removeFavorite(assetSetID: String) -> Bool {
        guard let row = favorites.first(where: { $0.assetSetID == assetSetID }) else { return false }
        guard (try? outbox.enqueue(.favoriteRemove(rowID: row.id, assetSetID: assetSetID))) != nil else { return false }
        refresh()
        return true
    }

    func toggleFavorite(assetSetID: String) {
        if isFavorited(assetSetID: assetSetID) {
            removeFavorite(assetSetID: assetSetID)
        } else {
            addFavorite(assetSetID: assetSetID)
        }
    }
}
