import XCTest
@testable import Playstead

/// Covers plan 03-06 task 3's `<acceptance_criteria>`.
final class FilterTests: XCTestCase {
    private var tempRoot: URL!
    private var localStore: LocalStore!
    private var catalogueStore: CatalogueStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        catalogueStore = CatalogueStore(localStore: localStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func seed(id: String, title: String, system: String, filename: String) throws {
        let entry = CatalogueEntry(
            id: id,
            system: system,
            displayTitle: title,
            tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: nil, size: nil, name: filename)]
        )
        try catalogueStore.upsert(entry)
    }

    // MARK: - Search

    func testSearchMatchesOriginalFilenameSubstringNotPresentInDisplayTitle() throws {
        try seed(id: "game-1", title: "Metroid Fusion", system: "gba", filename: "metroid4(usa).gba")

        let results = catalogueStore.filteredQuery(searchTerm: "usa")
        XCTAssertEqual(results.map(\.id), ["game-1"])
    }

    func testSearchMatchingNothingYieldsZeroEntryCountAndANoMatchesStateWithTheQueryAndAClearControl() throws {
        try seed(id: "game-1", title: "Metroid Fusion", system: "gba", filename: "metroid4.gba")

        let results = catalogueStore.filteredQuery(searchTerm: "zzz-does-not-exist")
        XCTAssertEqual(results.count, 0)

        let engine = makeUnusedSyncEngine()
        let curationStore = CurationStore(localStore: localStore)
        let viewModel = LibraryViewModel(catalogueStore: catalogueStore, curationStore: curationStore, syncEngine: engine)
        viewModel.searchTerm = "zzz-does-not-exist"

        let state = try XCTUnwrap(viewModel.searchResultState)
        XCTAssertEqual(state.entryCount, 0)
        XCTAssertTrue(state.heading.contains("zzz-does-not-exist"))
        XCTAssertEqual(state.clearControlLabel, "Clear search")
    }

    func testSearchDiacriticAndCaseInsensitive() throws {
        try seed(id: "game-1", title: "Pokémon", system: "gba", filename: "pokemon.gba")

        XCTAssertEqual(catalogueStore.filteredQuery(searchTerm: "POKEMON").map(\.id), ["game-1"])
        XCTAssertEqual(catalogueStore.filteredQuery(searchTerm: "pokémon").map(\.id), ["game-1"])
    }

    // MARK: - Filter chip intersection

    func testCombiningSystemChipAndAvailabilityChipNarrowsToTheIntersection() throws {
        try seed(id: "gba-server", title: "GBA Server Only", system: "gba", filename: "a.gba")
        try seed(id: "gba-ready", title: "GBA Ready", system: "gba", filename: "b.gba")
        try seed(id: "snes-ready", title: "SNES Ready", system: "snes", filename: "c.smc")

        try catalogueStore.setAvailability(id: "gba-ready", availability: "ready_offline")
        try catalogueStore.setAvailability(id: "snes-ready", availability: "ready_offline")

        let intersection = catalogueStore.filteredQuery(systemID: "gba", availability: "ready_offline")
        XCTAssertEqual(intersection.map(\.id), ["gba-ready"])
    }

    func testPressedChipIsSelectedAccordingToTheSharedSelectionModel() {
        let chip = FilterChip(id: "gba", label: "Game Boy Advance")
        let otherChip = FilterChip(id: "snes", label: "Super Nintendo")

        XCTAssertTrue(FilterChipRow.isSelected(chip, selectedID: "gba"))
        XCTAssertFalse(FilterChipRow.isSelected(otherChip, selectedID: "gba"))
        XCTAssertFalse(FilterChipRow.isSelected(chip, selectedID: nil))
    }

    // MARK: - Show all systems

    func testSystemsWithZeroEntriesAreHiddenUntilShowAllIsActivatedAndTheControlStatesTheHiddenCount() throws {
        try seed(id: "gba-1", title: "GBA Game", system: "gba", filename: "a.gba")

        let engine = makeUnusedSyncEngine()
        let curationStore = CurationStore(localStore: localStore)
        let viewModel = LibraryViewModel(catalogueStore: catalogueStore, curationStore: curationStore, syncEngine: engine)

        XCTAssertEqual(viewModel.nonEmptySystemIDs, ["gba"])
        // All 7 registry systems minus the 1 non-empty one = 6 hidden.
        XCTAssertEqual(viewModel.hiddenSystemIDs.count, 6)
        XCTAssertFalse(viewModel.hiddenSystemIDs.contains("gba"))

        let label = ShowAllSystemsControl.label(hiddenCount: viewModel.hiddenSystemIDs.count, isExpanded: false)
        XCTAssertTrue(label.contains("6"))
        XCTAssertTrue(label.contains("hidden"))

        let expandedLabel = ShowAllSystemsControl.label(hiddenCount: viewModel.hiddenSystemIDs.count, isExpanded: true)
        XCTAssertEqual(expandedLabel, "Hide empty systems")
    }

    // MARK: - Offline browse

    func testLibraryRendersFullEntryCountWithEveryNetworkRequestStubbedToFailAndExposesLastSyncedTimestamp() async throws {
        try seed(id: "game-1", title: "Metroid Fusion", system: "gba", filename: "metroid.gba")
        try seed(id: "game-2", title: "Zelda", system: "gba", filename: "zelda.gba")

        let cursorStore = CursorStore(localStore: localStore)
        try cursorStore.store(OpaqueCursor(rawValue: "CUR1"), syncedAt: Date())

        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], bodyChunks: [], failAfter: true)
        }
        let apiClient = APIClient(
            keychain: KeychainStore(),
            session: StubURLProtocol.makeSession(),
            credential: PairingCredential(deviceID: "d", baseURL: URL(string: "https://sync.test")!, token: "t")
        )
        let engine = SyncEngine(apiClient: apiClient, localStore: localStore)
        await engine.syncNow()

        let curationStore = CurationStore(localStore: localStore)
        let viewModel = LibraryViewModel(catalogueStore: catalogueStore, curationStore: curationStore, syncEngine: engine)
        await viewModel.refreshSyncState()
        viewModel.refresh()

        XCTAssertEqual(viewModel.catalogue.count, 2, "the last-synced local read model must still render in full")
        XCTAssertTrue(viewModel.isOffline)
        XCTAssertNotNil(viewModel.lastSyncedDescription())

        StubURLProtocol.reset()
    }

    // MARK: - Helpers

    private func makeUnusedSyncEngine() -> SyncEngine {
        let apiClient = APIClient(
            keychain: KeychainStore(),
            session: StubURLProtocol.makeSession(),
            credential: PairingCredential(deviceID: "d", baseURL: URL(string: "https://sync.test")!, token: "t")
        )
        return SyncEngine(apiClient: apiClient, localStore: localStore)
    }
}
