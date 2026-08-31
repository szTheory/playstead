import Foundation

/// Publishes the library's sections from the local read model + sync
/// state (03-UI-SPEC.md Navigation & IA, Copywriting Contract, Status
/// Vocabulary). Never begins a download on the user's behalf; when the
/// catalogue is non-empty on a freshly paired device, shows the
/// dismissible first-run banner exactly once. Empty curation shelves are
/// omitted from Home while their sidebar entries remain, each with a
/// one-line explanation (`ShelfView`'s `emptyExplanation`).
@Observable
final class LibraryViewModel {
    private let catalogueStore: CatalogueStore
    private let curationStore: CurationStore
    private let syncEngine: SyncEngine

    private(set) var catalogue: [CatalogueEntry] = []
    private(set) var favorites: [CurationFavoriteRow] = []
    private(set) var syncState: SyncState = .neverSynced
    var isFirstRunBannerDismissed = false

    init(catalogueStore: CatalogueStore, curationStore: CurationStore, syncEngine: SyncEngine) {
        self.catalogueStore = catalogueStore
        self.curationStore = curationStore
        self.syncEngine = syncEngine
        refresh()
    }

    /// Re-reads the catalogue/curation stores from disk. The library
    /// renders whatever is already local — this never triggers a network
    /// request itself; `refreshSyncState()` (below) observes whatever
    /// `SyncEngine.syncNow()` a caller separately drove.
    func refresh() {
        catalogue = catalogueStore.fetchAll()
        favorites = curationStore.fetchFavorites()
    }

    func refreshSyncState() async {
        syncState = await syncEngine.state
    }

    var isEmpty: Bool { catalogue.isEmpty }

    var shouldShowFirstRunBanner: Bool {
        !catalogue.isEmpty && !isFirstRunBannerDismissed
    }

    func dismissFirstRunBanner() {
        isFirstRunBannerDismissed = true
    }

    /// Every system id present in the catalogue with at least one entry.
    var nonEmptySystemIDs: Set<String> {
        Set(catalogue.map(\.system))
    }

    var hasUnidentifiedEntries: Bool {
        catalogue.contains { $0.system == "unknown" || $0.displayTitle.isEmpty }
    }
}
