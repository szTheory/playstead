import SwiftUI

/// The app's real navigation shell: `SidebarView`'s canonical section
/// order on the left, and the section's own surface on the right.
///
/// Every curation surface it routes to (`ContinueShelfView`,
/// `FavoritesShelfView`, `CollectionsView`/`CollectionDetailView`,
/// `QueueShelfView`, `RecentShelfView`) is driven by the *shared* view
/// model instance `AppEnvironment` constructed — never a locally built
/// one — so all five curation nouns read and write one `CurationStore`
/// and one `Outbox`. Until this view existed, those components were
/// constructed only in tests and were unreachable from the shipped app
/// (P4-WR-003).
struct LibraryShellView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: SidebarSection? = .home
    @State private var selectedCollectionID: String?
    @State private var refreshError: String?
    @State private var presentedSurface: ShellSurface?
    @State private var searchText = ""
    @State private var libraryLayout: LibraryLayout = .cards
    @State private var catalogueGridColumnCount = 1
    @State private var selectedSettingsPane: SettingsPane = .storage
    /// The list layout's ordering. Lives here rather than in
    /// `LibraryViewModel` because it is presentation state, and it governs
    /// the rows `catalogueList` renders -- which is the whole of WINDOWS
    /// #79: `LibrarySortOption` existed and was tested, and nothing in the
    /// shipped app could reach it, because the shipped list renders
    /// `GameRowView`. The unreachable `GameListView` it was written for has
    /// since been deleted.
    @State private var librarySort: LibrarySortOption = .title
    @State private var selectedListEntryID: String?
    @State private var downloadCommand: LibraryDownloadCommand?
    @State private var downloadCommandSequence = 0
    @FocusState private var focusedSheetDismissal: Bool
    @FocusState private var libraryListHasFocus: Bool
    @FocusState private var sidebarHasFocus: Bool
    @FocusState private var searchFieldHasFocus: Bool
    @FocusState private var collectionNameHasFocus: Bool
    @State private var navigationDispatcher = ControllerNavigationDispatcher()
    @State private var controllerFocusedAssetSetID: String?
    @State private var controllerFocusedCollectionID: String?
    @State private var controllerFocusedFilterID: String?
    @State private var controllerCommandSequence = 0
    @State private var controllerCommand: LibraryControllerCommand?
    /// Bumped by every storage action so the presented sheet re-reads the
    /// real stores. Pins, the queue and the quota policy live in SQLite,
    /// not in an observable view model, so nothing else would invalidate
    /// the sheet's body.
    @State private var storageRevision = 0
    @State private var showsControllerTest = false

    /// Pairing is a focused task. Downloads, storage, and emulator setup
    /// are persistent destinations rather than large modal sheets.
    enum ShellSurface: String, Identifiable, CaseIterable {
        case pairing

        var id: String { rawValue }
    }

    enum SettingsPane: String, CaseIterable, Identifiable {
        case storage
        case emulator
        case controller

        var id: String { rawValue }
        var accessibilityIdentifier: String {
            switch self {
            case .storage: AccessibilityIdentifiers.Control.openStorage
            case .emulator: AccessibilityIdentifiers.Control.openAdapter
            case .controller: AccessibilityIdentifiers.Control.openControllerSettings
            }
        }
        var title: String {
            switch self {
            case .storage: "Storage"
            case .emulator: "Emulator"
            case .controller: "Controller"
            }
        }
    }

    enum LibraryLayout: Hashable {
        case cards
        case list
    }

    /// The command label and sheet title for each surface — a pure
    /// function, so a test can assert every surface actually routes
    /// somewhere rather than opening a blank sheet.
    static func title(for surface: ShellSurface) -> String {
        switch surface {
        case .pairing: return "Pairing"
        }
    }

    static func surfaceIdentifier(for surface: ShellSurface) -> String {
        switch surface {
        case .pairing: return AccessibilityIdentifiers.Surface.pairing
        }
    }

    private var library: LibraryViewModel { environment.libraryViewModel }

    /// Curation rows reference an asset set id; the shelves need the
    /// catalogue entry behind it to render a title. Built once per body
    /// evaluation from the already-local catalogue — no query.
    private var catalogueByAssetSetID: [String: CatalogueEntry] {
        Dictionary(library.catalogue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var sidebarEntries: [SidebarEntry] {
        SidebarView.entries(nonEmptySystemIDs: library.nonEmptySystemIDs, hasUnidentified: library.hasUnidentifiedEntries)
    }

    private var collectionIDs: [String] {
        environment.collectionsViewModel.collections.map(\.id)
    }

    private var collectionMemberIDs: [String] {
        guard let selectedCollectionID else { return [] }
        return environment.collectionsViewModel.members(of: selectedCollectionID).map(\.assetSetID)
    }

    private var libraryFilterChips: [FilterChip] {
        let systems = availableSystemFilters.map {
            FilterChip(id: "system:\($0.id)", label: "System: \($0.label)")
        }
        let availability = AvailabilityVocabulary.values.compactMap { value -> FilterChip? in
            guard let label = AvailabilityVocabulary.label(value) else { return nil }
            return FilterChip(id: "availability:\(value)", label: "Availability: \(label)")
        }
        return [FilterChip(id: "system:all", label: "System: All systems")] + systems
            + [FilterChip(id: "availability:all", label: "Availability: Any")] + availability
    }

    private var selectedLibraryFilterIDs: Set<String> {
        [
            "system:\(library.selectedSystemID ?? "all")",
            "availability:\(library.selectedAvailability ?? "all")"
        ]
    }

    private var navigationContext: LibraryNavigationContext {
        if selection == .collections {
            return LibraryNavigationContext(
                sidebarCount: sidebarEntries.count,
                contentCount: collectionMemberIDs.count,
                contentColumnCount: 1,
                filterCount: 0,
                surface: .collections,
                collectionCount: collectionIDs.count,
                collectionMemberCount: collectionMemberIDs.count,
                hasSelectedCollection: selectedCollectionID.map(collectionIDs.contains) ?? false
            )
        }
        return LibraryNavigationContext(
            sidebarCount: sidebarEntries.count,
            contentCount: visibleContentEntryIDs.count,
            contentColumnCount: selection == .home && libraryLayout == .cards ? catalogueGridColumnCount : 1,
            filterCount: selection == .home ? libraryFilterChips.count : 0,
            surface: .games,
            collectionCount: 0,
            collectionMemberCount: 0,
            hasSelectedCollection: false
        )
    }

    /// Stable IDs for the games users can act on in the selected destination.
    /// Session-only records and settings have no game activation target.
    private var visibleContentEntryIDs: [String] {
        switch selection ?? .home {
        case .home: library.filteredCatalogue.map(\.id)
        case .recentlyPlayed: environment.continueViewModel.items.map(\.assetSetID)
        case .favorites: environment.favoritesViewModel.favorites.map(\.assetSetID)
        case .collections: collectionMemberIDs
        case .queue: environment.queueViewModel.items.map(\.assetSetID)
        case .recent: environment.recentViewModel.items.map(\.assetSetID)
        case .downloads, .settings: []
        case .system(let id): library.catalogue(forSystemID: id).map(\.id)
        case .unidentified: library.unidentifiedCatalogue.map(\.id)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                nonEmptySystemIDs: library.nonEmptySystemIDs,
                hasUnidentified: library.hasUnidentifiedEntries,
                selection: $selection
            )
            .focused($sidebarHasFocus)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Self.title(for: selection ?? .home))
#if UI_TESTING
                .overlay {
                // MC-02 test-only observability (see
                // `AppEnvironment.uiTestConsoleExportAttempts`): renders
                // the most recent export URL `openConsoleSavesExport`
                // resolved, so a front-door journey can prove the
                // default "Export saves…" button performed a real
                // action distinct from a bare dismissal, without a real
                // browser ever launching during automated tests.
                Text(environment.uiTestConsoleExportAttempts.last ?? "")
                    .accessibilityIdentifier("playstead.harness.console-export-attempt")
                    .accessibilityHidden(environment.uiTestConsoleExportAttempts.isEmpty)
                    .frame(width: 0, height: 0)
                }
#endif
        }
        .sheet(item: $presentedSurface) { surface in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                surfaceContent(surface)
                HStack {
                    Spacer()
                    Button("Done") { presentedSurface = nil }
                        .focused($focusedSheetDismissal)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Control.done)
                        .overlay {
                            RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                                .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                                .opacity(PlaysteadFocusRing.opacity(isFocused: focusedSheetDismissal))
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
            .environment(environment)
            .frame(minWidth: 560, minHeight: 260)
            .background(DesignTokens.background.ignoresSafeArea())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.title(for: surface))
            .accessibilityIdentifier(Self.surfaceIdentifier(for: surface))
            .focusSection()
            .defaultFocus($focusedSheetDismissal, true)
            // See `sheet-focus-placement-test.sh`: `.defaultFocus` alone is not
            // observed to land in this app for a `.sheet`-presented view, whose
            // window is not yet key when `onAppear` runs. Hop one runloop first.
            .onAppear { placeInitialSheetFocus() }
            .onExitCommand { presentedSurface = nil }
        }
        .task {
            // The window renders from the local mirror first (LIBR-01's
            // browse-before-download contract); the network pass is a
            // refresh, never a gate.
            library.refresh()
            environment.refreshCurationViewModels()
            await environment.syncNow()
        }
        // The app menu's "Pair with Server…" command is the second
        // reachable call site the ceremony needs — a user who is already
        // paired must be able to re-pair against a new server, not only a
        // fresh install seeing the empty-state action button.
        .onReceive(NotificationCenter.default.publisher(for: .presentPairingSheetRequested)) { _ in
            presentedSurface = .pairing
        }
        .onChange(of: environment.controllerHost.liveInputs) { previous, current in
            guard let controllerID = environment.controllerHost.assignedControllerID else { return }
            for input in previous.subtracting(current).sorted() {
                let effect = navigationDispatcher.receive(
                    inputName: input, active: false,
                    context: navigationContext
                )
                applyNavigationEffect(effect)
            }
            for input in current.subtracting(previous).sorted() {
                let effect = navigationDispatcher.receive(
                    inputName: input, active: true,
                    context: navigationContext
                )
                applyNavigationEffect(effect, controllerID: controllerID)
            }
        }
        .onChange(of: selection) { _, selected in
            guard let selected, let index = sidebarEntries.firstIndex(where: { $0.section == selected }) else { return }
            navigationDispatcher.synchronizeSidebar(index: index)
        }
        .onChange(of: selectedListEntryID) { _, selectedID in
            guard let selectedID, let index = visibleContentEntryIDs.firstIndex(of: selectedID) else { return }
            navigationDispatcher.synchronizeContent(index: index)
            controllerFocusedAssetSetID = selectedID
        }
        .onChange(of: selectedCollectionID) { _, selectedID in
            guard selection == .collections,
                  let selectedID,
                  let index = collectionIDs.firstIndex(of: selectedID) else { return }
            controllerFocusedCollectionID = selectedID
            navigationDispatcher.synchronizeCollections(index: index)
        }
        .onMoveCommand { direction in
            // Collection-name focus is available at the deployment floor.
            // Search focus is explicit on macOS 15+; macOS 14 has no SwiftUI
            // searchable focus binding, so only a non-empty query can be guarded.
            if #available(macOS 15.0, *) {
                guard !searchFieldHasFocus, !collectionNameHasFocus else { return }
            } else {
                guard !collectionNameHasFocus, searchText.isEmpty else { return }
            }
            let command: LibraryNavigationCommand
            switch direction {
            case .up: command = .up
            case .down: command = .down
            case .left: command = .left
            case .right: command = .right
            @unknown default: return
            }
            let effect = navigationDispatcher.move(
                command,
                context: navigationContext
            )
            applyNavigationEffect(effect)
        }
    }

    /// The sheet's dismissal control owns focus the moment it appears, so a
    /// keyboard user always has a defined starting point and a visible ring.
    private func placeInitialSheetFocus() {
        Task { @MainActor in
            await Task.yield()
            focusedSheetDismissal = true
        }
    }

    /// Each command-bar surface's real content. Every value handed to these
    /// views is read from the app's shared stores at body-evaluation time
    /// and every callback does real work against them — no placeholders,
    /// no locally-constructed second copy of a store.
    @ViewBuilder
    private func surfaceContent(_ surface: ShellSurface) -> some View {
        // Read so a storage action invalidates this body; pins, the queue
        // and the quota policy live in SQLite, not in a view model.
        let _ = storageRevision

        switch surface {
        case .pairing:
            PairingView()
        }
    }

    /// The navigation title for each section — a pure function so a test
    /// can assert every section actually routes somewhere rather than
    /// falling through to a blank pane.
    static func title(for section: SidebarSection) -> String {
        switch section {
        case .home: return "All Games"
        case .recentlyPlayed: return "Recently Played"
        case .favorites: return "Favorites"
        case .collections: return "Collections"
        case .queue: return "Queue"
        case .recent: return "Recent"
        case .downloads: return "Downloads"
        case .system(let id): return SystemRegistry.entry(for: id).displayName
        case .unidentified: return "Unidentified"
        case .settings: return "Settings"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            homeLibrary
        case .recentlyPlayed:
            ContinueShelfView(
                viewModel: environment.continueViewModel,
                catalogueByAssetSetID: catalogueByAssetSetID,
                onBrowseLibrary: { selection = .home },
                controllerFocusedAssetSetID: controllerFocusedAssetSetID,
                controllerCommand: controllerCommand
            )
        case .favorites:
            FavoritesShelfView(
                viewModel: environment.favoritesViewModel,
                catalogueByAssetSetID: catalogueByAssetSetID,
                onBrowseLibrary: { selection = .home },
                controllerFocusedAssetSetID: controllerFocusedAssetSetID,
                controllerCommand: controllerCommand,
                // Retained as the pure status projection used by the
                // shelf's item contract; GameRowView derives the same
                // live status and owns the actionable controls.
                statuses: { assetSetID in
                    guard let entry = catalogueByAssetSetID[assetSetID] else { return [] }
                    return environment.libraryStatuses(for: entry)
                }
            )
        case .collections:
            collectionsDetail
        case .queue:
            QueueShelfView(
                viewModel: environment.queueViewModel,
                catalogueByAssetSetID: catalogueByAssetSetID,
                onBrowseLibrary: { selection = .home },
                controllerFocusedAssetSetID: controllerFocusedAssetSetID,
                controllerCommand: controllerCommand
            )
        case .recent:
            RecentShelfView(
                viewModel: environment.recentViewModel,
                catalogueByAssetSetID: catalogueByAssetSetID,
                onBrowseLibrary: { selection = .home },
                controllerFocusedAssetSetID: controllerFocusedAssetSetID,
                controllerCommand: controllerCommand
            )
        case .downloads:
            downloadsDetail
        case .system(let id):
            catalogueList(library.catalogue(forSystemID: id))
        case .unidentified:
            catalogueList(library.unidentifiedCatalogue)
        case .settings:
            settingsDetail
        }
    }

    private var downloadsDetail: some View {
        // Queue rows are read from durable storage. Mutating one of them
        // bumps this revision so the persistent Downloads destination
        // reconstructs its projection after pause/resume/reorder actions.
        let _ = storageRevision
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let blocked = environment.lastBlockedDownload {
                Label(blocked.reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                Button("Open Storage Settings") { selection = .settings; selectedSettingsPane = .storage }
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }

            DownloadsView(
                rows: environment.downloadRows(),
                onPause: { environment.pauseDownload(id: $0); storageRevision += 1 },
                onResume: { environment.resumeDownload(id: $0); storageRevision += 1 },
                onCancel: { environment.cancelDownload(id: $0); storageRevision += 1 },
                onMoveUp: { environment.moveDownloadUp(id: $0); storageRevision += 1 },
                onMoveDown: { environment.moveDownloadDown(id: $0); storageRevision += 1 },
                onBrowseLibrary: { selection = .home }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await environment.startDownloadQueue() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Downloads")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.downloads)
    }

    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Picker("Settings", selection: $selectedSettingsPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Text(pane.title)
                        .accessibilityIdentifier(pane.accessibilityIdentifier)
                        .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding(.horizontal, DesignTokens.Spacing.md)

            ScrollView {
                Group {
                    switch selectedSettingsPane {
                    case .storage:
                        storageSettings
                    case .emulator:
                        AdapterSetupView()
                    case .controller:
                        controllerSettings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playstead.settings")
    }

    private var controllerSettings: some View {
        ControllerSettingsView(
            connectedControllers: environment.controllerHost.connectedControllers,
            assignedControllerID: environment.controllerHost.assignedControllerID,
            mapping: environment.controllerMappingStore.mapping(
                forControllerProductID: environment.controllerHost.assignedControllerID ?? ""
            ),
            showsMappingControls: false,
            onAssign: { environment.controllerHost.assign(controllerID: $0) },
            onOpenTestView: { showsControllerTest = true }
        )
        .sheet(isPresented: $showsControllerTest) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack {
                    Text("Controller test").font(.psHeading)
                    Spacer()
                    Button("Done") { showsControllerTest = false }
                }
                if let descriptor = environment.controllerHost.connectedControllers.first(where: {
                    $0.id == environment.controllerHost.assignedControllerID
                }) {
                    ControllerTestView(
                        controllerName: descriptor.name,
                        availableInputs: descriptor.availableInputs,
                        liveInputs: environment.controllerHost.liveInputs
                    )
                } else {
                    Text("No active controller is connected.")
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(minWidth: 440, minHeight: 300)
            .background(DesignTokens.background.ignoresSafeArea())
        }
    }

    private var storageSettings: some View {
        let _ = storageRevision
        let snapshot = environment.storageSnapshot()
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            QuotaSettingsView(
                policy: snapshot.policy,
                usedBytes: snapshot.usedBytes,
                onSetQuota: { environment.setQuota(bytes: $0); storageRevision += 1 }
            )
            StorageView(
                totalUsedBytes: snapshot.usedBytes,
                quotaBytes: snapshot.policy.quotaBytes,
                floorBytes: snapshot.policy.floorBytes,
                candidates: snapshot.candidates,
                pinnedGames: snapshot.pinnedGames,
                unreferencedObjects: snapshot.unreferenced,
                quarantinedPartials: snapshot.quarantined,
                onReclaim: { environment.reclaim(gameIDs: $0); storageRevision += 1 },
                onRemoveQuarantined: { environment.removeQuarantinedPartial(atPath: $0); storageRevision += 1 },
                onlyOnThisMacCounts: snapshot.onlyOnThisMacCounts,
                onExportOnlyCopy: { ids in
                    Task { await environment.openConsoleSavesExport(forAssetSetIDs: ids) }
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage settings")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.storage)
    }

    private var homeLibrary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            libraryControls

            switch libraryLayout {
            case .cards:
                // The cards layout had its own near-miss of the same contract
                // (WINDOWS #83): ShelfView's emptyExplanation is not blank,
                // but it echoes no query and offers no clear control, so
                // `clearSearch()` was unreachable here too.
                if let state = library.searchResultState {
                    NoMatchesView(state: state) { library.clearSearch() }
                } else {
                    catalogueCards
                }
            case .list:
                catalogueList(library.filteredCatalogue)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.md)
        .searchable(
            text: Binding(
                get: { searchText },
                set: { value in
                    searchText = value
                    library.searchTerm = value
                }
            ),
            placement: .toolbar,
            prompt: "Search your library"
        )
        .modifier(SupportedSearchFieldFocus(focus: $searchFieldHasFocus))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.library)
    }

    private var availableSystemFilters: [FilterChip] {
        var result = SystemRegistry.all
            .filter { library.nonEmptySystemIDs.contains($0.id) }
            .map { FilterChip(id: $0.id, label: $0.displayName) }
        if library.hasUnidentifiedEntries {
            result.append(FilterChip(id: "unidentified", label: SystemRegistry.unknown.displayName))
        }
        return result
    }

    private func toggleLibraryFilter(_ id: String) {
        if id == "system:all" {
            library.selectedSystemID = nil
        } else if id.hasPrefix("system:") {
            let systemID = String(id.dropFirst("system:".count))
            guard availableSystemFilters.contains(where: { $0.id == systemID }) else { return }
            library.selectedSystemID = systemID
        } else if id == "availability:all" {
            library.selectedAvailability = nil
        } else if id.hasPrefix("availability:") {
            let availability = String(id.dropFirst("availability:".count))
            guard AvailabilityVocabulary.values.contains(availability) else { return }
            library.selectedAvailability = availability
        }
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            libraryLayoutPicker
                .frame(maxWidth: .infinity, alignment: .leading)

            FilterChipRow(
                chips: libraryFilterChips,
                selectedIDs: selectedLibraryFilterIDs,
                controllerFocusedID: controllerFocusedFilterID,
                onToggle: toggleLibraryFilter
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Surface.filter)

            if libraryLayout == .list {
                listOnlyControls
            }
        }
        // Keep the view switch in the library content so searchable toolbar
        // pressure and narrow windows cannot collapse its click target. Filter
        // and list-only controls stay below it, so their state never moves it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryLayoutPicker: some View {
        Picker("Library view", selection: $libraryLayout) {
            Image(systemName: "square.grid.2x2")
                .accessibilityLabel("Cards")
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.showCards)
                .tag(LibraryLayout.cards)
            Image(systemName: "list.bullet")
                .accessibilityLabel("List")
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.showList)
                .tag(LibraryLayout.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 104)
        .help("Choose Cards or List view")
        .accessibilityLabel("Library view")
        .accessibilityIdentifier("playstead.library.view-mode")
        .onChange(of: libraryLayout) { _, mode in
            if mode == .list { showLibraryList() }
        }
    }

    private var listOnlyControls: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Picker("Sort by", selection: $librarySort) {
                ForEach(LibrarySortOption.selectable, id: \.self) { option in
                    Text(option.controlLabel).tag(option)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("playstead.library.sort")

            Button("Download Selected") { requestSelectedDownload() }
                .accessibilityLabel("Download selected game")
                .disabled(selectedDownloadEntry == nil)
                .keyboardShortcut("d", modifiers: .command)
                .playsteadFocusable(identifier: "playstead.control.download-selected")
        }
    }

    /// Collections list and, once one is picked, that collection's
    /// members — `CollectionDetailView` needs a selected collection id,
    /// and `CollectionsView` publishes it through a binding.
    private var collectionsDetail: some View {
        HSplitView {
            CollectionsView(
                viewModel: environment.collectionsViewModel,
                selectedCollectionID: $selectedCollectionID,
                controllerFocusedCollectionID: controllerFocusedCollectionID,
                collectionNameFocus: $collectionNameHasFocus
            )
            .frame(minWidth: 200, maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)

            Group {
                if let selectedCollectionID {
                    CollectionDetailView(
                        viewModel: environment.collectionsViewModel,
                        collectionID: selectedCollectionID,
                        catalogueByAssetSetID: catalogueByAssetSetID,
                        controllerFocusedAssetSetID: controllerFocusedAssetSetID,
                        controllerCommand: controllerCommand
                    )
                } else {
                    Text("Select a collection to see what's in it.")
                        .font(.psBody)
                        .foregroundStyle(DesignTokens.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private func catalogueList(_ entries: [CatalogueEntry]) -> some View {
        let ordered = LibrarySortOption.sortedEntries(entries, by: librarySort)
        return List(selection: $selectedListEntryID) {
            ForEach(ordered) { entry in
                GameRowView(
                    entry: entry,
                    downloadCommand: downloadCommand,
                    isSelected: selectedListEntryID == entry.id,
                    isControllerFocused: controllerFocusedAssetSetID == entry.id,
                    controllerCommand: controllerCommand
                )
                    .tag(entry.id)
            }
        }
        .focused($libraryListHasFocus)
        .onAppear {
            // A sidebar return can construct the List before the window has
            // finished moving keyboard focus off the destination row. Place
            // List focus on the next main-actor turn so the native row
            // selection receives the next arrow key.
            Task { @MainActor in
                await Task.yield()
                libraryListHasFocus = true
            }
        }
        .listStyle(.inset)
        .accessibilityLabel("Game list")
        .accessibilityValue(
            ordered.first(where: { $0.id == selectedListEntryID })?.displayTitle ?? "No game selected"
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.gameList)
        .overlay {
            if entries.isEmpty { emptyListPane }
        }
    }

    /// The grid layout's cards. Split out of `libraryBody` so the cards case
    /// can branch to `NoMatchesView` without nesting the whole builder.
    private var catalogueCards: some View {
        GeometryReader { geometry in
            let columnCount = Self.gridColumnCount(for: geometry.size.width)
            let columns = Array(
                repeating: GridItem(.fixed(DesignTokens.CardGeometry.width), spacing: DesignTokens.Spacing.lg, alignment: .leading),
                count: columnCount
            )

            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: DesignTokens.Spacing.lg
                ) {
                    ForEach(library.filteredCatalogue) { entry in
                        GameRowView(
                            entry: entry,
                            presentation: .card,
                            isControllerFocused: controllerFocusedAssetSetID == entry.id,
                            controllerCommand: controllerCommand
                        )
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.md)
            }
            .onAppear { catalogueGridColumnCount = columnCount }
            .onChange(of: columnCount) { _, value in catalogueGridColumnCount = value }
            .overlay {
                if library.filteredCatalogue.isEmpty {
                    Text("No games match the current search and filters.")
                        .font(.psBody)
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game cards")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.gameCard)
    }

    static func gridColumnCount(
        for availableWidth: CGFloat,
        cardWidth: CGFloat = DesignTokens.CardGeometry.width,
        spacing: CGFloat = DesignTokens.Spacing.lg
    ) -> Int {
        guard availableWidth.isFinite, availableWidth > 0,
              cardWidth.isFinite, cardWidth > 0,
              spacing.isFinite, spacing >= 0 else { return 1 }
        return max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
    }

    /// What an empty list actually says. `LibraryViewModel.searchResultState`
    /// has been computed, unit-tested and snapshot-tested since Phase 3 with
    /// no view reading it, so a search that matched nothing fell through to
    /// the "No games yet" pane below and told an already-paired user with a
    /// full library to go pair (WINDOWS #83). 03-UI-SPEC's Copywriting
    /// Contract owns the no-matches copy; `NoMatchesView` renders it verbatim
    /// and is the only place `clearSearch()` is reachable from the UI.
    @ViewBuilder
    private var emptyListPane: some View {
        if let state = library.searchResultState {
            NoMatchesView(state: state) { library.clearSearch() }
        } else if !library.catalogue.isEmpty {
            // Non-empty library, nothing left after the active filters. Not
            // the search case, so it is not the Copywriting Contract's copy —
            // but it is emphatically not "No games yet" either.
            ContentUnavailableView(
                "No games match the current filters",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Clear a filter to see everything.")
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Surface.noMatches)
        } else {
            VStack(spacing: DesignTokens.Spacing.md) {
                ContentUnavailableView(
                    "No games yet",
                    systemImage: "square.stack.3d.up",
                    description: Text(refreshError ?? "Pair with your Playstead server to see your library.")
                )
                // The string above has named this action since Phase 3
                // with nothing behind it to reach (WINDOWS #54) — this
                // button is what makes it real.
                Button("Pair with Server…") { presentedSurface = .pairing }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Control.openPairing)
            }
        }
    }

    private var selectedDownloadEntry: CatalogueEntry? {
        guard let entry = library.filteredCatalogue.first(where: { $0.id == selectedListEntryID }),
              GameRowView.status(for: environment.readinessReport(for: entry)) == .needsDownload else {
            return nil
        }
        return entry
    }

    /// A macOS List owns keyboard selection; its embedded buttons are not a
    /// guaranteed Tab sequence. Activating List therefore establishes an
    /// exact selected row and moves focus into the List. Arrow keys change the
    /// selection and the single ⌘D command acts on only that selected row.
    private func showLibraryList() {
        let entries = library.filteredCatalogue
        if !entries.contains(where: { $0.id == selectedListEntryID }) {
            selectedListEntryID = entries.first?.id
        }
        libraryLayout = .list
    }

    private func requestSelectedDownload() {
        guard let entry = selectedDownloadEntry else { return }
        downloadCommandSequence += 1
        downloadCommand = LibraryDownloadCommand(
            sequence: downloadCommandSequence,
            assetSetID: entry.id
        )
    }

    private func applyNavigationEffect(_ effect: LibraryNavigationEffect?, controllerID _: String? = nil) {
        guard let effect else { return }
        switch effect {
        case .focusSidebar(let index):
            guard sidebarEntries.indices.contains(index) else { return }
            selection = sidebarEntries[index].section
            controllerFocusedAssetSetID = nil
            controllerFocusedCollectionID = nil
            controllerFocusedFilterID = nil
            sidebarHasFocus = true
            libraryListHasFocus = false
        case .focusFilter(let index):
            guard libraryFilterChips.indices.contains(index) else { return }
            controllerFocusedAssetSetID = nil
            controllerFocusedCollectionID = nil
            controllerFocusedFilterID = libraryFilterChips[index].id
            sidebarHasFocus = false
            libraryListHasFocus = false
        case .focusCollection(let index):
            guard collectionIDs.indices.contains(index) else { return }
            let collectionID = collectionIDs[index]
            controllerFocusedAssetSetID = nil
            controllerFocusedFilterID = nil
            controllerFocusedCollectionID = collectionID
            selectedCollectionID = collectionID
            sidebarHasFocus = false
            libraryListHasFocus = false
        case .focusContent(let index):
            let targets = visibleContentEntryIDs
            guard targets.indices.contains(index) else { return }
            let assetSetID = targets[index]
            controllerFocusedAssetSetID = assetSetID
            controllerFocusedCollectionID = nil
            controllerFocusedFilterID = nil
            sidebarHasFocus = false
            if selection == .home || isSystemSelection || selection == .unidentified {
                selectedListEntryID = assetSetID
                libraryListHasFocus = libraryLayout == .list
            }
        case .focusCollectionMember(let index):
            guard collectionMemberIDs.indices.contains(index) else { return }
            controllerFocusedAssetSetID = collectionMemberIDs[index]
            controllerFocusedCollectionID = nil
            controllerFocusedFilterID = nil
            sidebarHasFocus = false
            libraryListHasFocus = false
        case .selectCollection(let index):
            guard collectionIDs.indices.contains(index) else { return }
            selectedCollectionID = collectionIDs[index]
            controllerFocusedCollectionID = collectionIDs[index]
        case .toggleFilter(let index):
            guard libraryFilterChips.indices.contains(index) else { return }
            let chip = libraryFilterChips[index]
            controllerFocusedFilterID = chip.id
            toggleLibraryFilter(chip.id)
        case .activateContent(let index):
            let targets = navigationDispatcher.region == .collectionMembers
                ? collectionMemberIDs
                : visibleContentEntryIDs
            guard targets.indices.contains(index) else { return }
            sendControllerCommand(for: targets[index], action: .activate)
        case .openContextAction(let index):
            let targets = navigationDispatcher.region == .collectionMembers
                ? collectionMemberIDs
                : visibleContentEntryIDs
            guard targets.indices.contains(index) else { return }
            sendControllerCommand(for: targets[index], action: .context)
        }
    }

    private var isSystemSelection: Bool {
        if case .system = selection { return true }
        return false
    }

    private func sendControllerCommand(for assetSetID: String, action: LibraryControllerCommand.Action) {
        controllerCommandSequence += 1
        controllerCommand = LibraryControllerCommand(
            sequence: controllerCommandSequence,
            assetSetID: assetSetID,
            action: action
        )
    }
}

/// SwiftUI exposed search-field focus binding in macOS 15. Keep the app's
/// macOS 14 deployment target; on older systems the non-empty query guard
/// still protects active search editing from arrow navigation.
private struct SupportedSearchFieldFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(focus)
        } else {
            content
        }
    }
}

extension AppEnvironment {
    /// Returns the API client only when a paired credential actually
    /// exists — avoids surfacing `.notPaired` as a scary-looking error on
    /// a fresh, unpaired install.
    func apiClientIfAvailable() async -> APIClient? {
#if UI_TESTING
        guard !uiTestingBlocksExternalIO else { return nil }
#endif
        guard let client = apiClient else { return nil }
        let hasCredential = await client.credential != nil
        return hasCredential ? client : nil
    }
}
