import Foundation

/// The "no matches" explanation (03-UI-SPEC.md Copywriting Contract) —
/// never a blank pane.
struct SearchResultState: Equatable {
    let query: String
    let entryCount: Int
    var heading: String { "No matches for \u{201C}\(query)\u{201D}" }
    let body = "Check the spelling, or clear your search to see everything."
    let clearControlLabel = "Clear search"
}

/// Publishes the library's sections, search/filter results, and sync
/// state from the local read model (03-UI-SPEC.md Navigation & IA,
/// Copywriting Contract, Status Vocabulary). Never begins a download on
/// the user's behalf; when the catalogue is non-empty on a freshly
/// paired device, shows the dismissible first-run banner exactly once.
/// Empty curation shelves are omitted from Home while their sidebar
/// entries remain, each with a one-line explanation (`ShelfView`'s
/// `emptyExplanation`).
@Observable
final class LibraryViewModel {
    private let catalogueStore: CatalogueStore
    private let curationStore: CurationStore
    private let syncEngine: SyncEngine

    private(set) var catalogue: [CatalogueEntry] = []
    private(set) var favorites: [CurationFavoriteRow] = []
    private(set) var syncState: SyncState = .neverSynced
    var isFirstRunBannerDismissed = false
    var isShowingAllSystems = false

    var searchTerm: String = "" { didSet { refreshFiltered() } }
    var selectedSystemID: String? { didSet { refreshFiltered() } }
    var selectedAvailability: String? { didSet { refreshFiltered() } }
    private(set) var filteredCatalogue: [CatalogueEntry] = []

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
        refreshFiltered()
    }

    private func refreshFiltered() {
        filteredCatalogue = catalogueStore.filteredQuery(
            searchTerm: searchTerm, systemID: selectedSystemID, availability: selectedAvailability
        )
    }

    func refreshSyncState() async {
        syncState = await syncEngine.state
    }

    var isEmpty: Bool { catalogue.isEmpty }

    /// The Mac client still renders from the local read model when the
    /// network is unreachable (03-UI-SPEC.md Copywriting Contract's
    /// offline indicator, EXPERIENCE-ETHOS #7) — offline is a normal
    /// state, not an error page.
    var isOffline: Bool {
        if case .offline = syncState { return true }
        return false
    }

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

    /// Registry systems with zero entries — hidden behind
    /// `ShowAllSystemsControl` until expanded. LIBR-04's literal
    /// mechanism: driven by emptiness, never a persisted preference toggle.
    var hiddenSystemIDs: [String] {
        SystemRegistry.all.map(\.id).filter { !nonEmptySystemIDs.contains($0) }
    }

    var hasUnidentifiedEntries: Bool {
        catalogue.contains { $0.system == "unknown" || $0.displayTitle.isEmpty }
    }

    /// "Last synced {relative time}" copy for the offline indicator
    /// (03-UI-SPEC.md Copywriting Contract) — never "Offline" alone, and
    /// never an error styling; offline browsing of a converged local
    /// model is the normal, intended state (EXPERIENCE-ETHOS #7).
    func lastSyncedDescription(now: Date = Date()) -> String? {
        switch syncState {
        case .synced(let at), .offline(let at):
            let formatter = RelativeDateTimeFormatter()
            return "Last synced \(formatter.localizedString(for: at, relativeTo: now))"
        case .neverSynced, .syncing:
            return nil
        }
    }

    /// The no-matches search result state, or `nil` when there's nothing
    /// to explain (an empty query, or a query that did match something).
    var searchResultState: SearchResultState? {
        guard !searchTerm.isEmpty, filteredCatalogue.isEmpty else { return nil }
        return SearchResultState(query: searchTerm, entryCount: filteredCatalogue.count)
    }

    func clearSearch() {
        searchTerm = ""
    }
}
