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
    @State private var presentedReadinessEntry: CatalogueEntry?
    @FocusState private var focusedShellControl: ShellSurface?
    /// Bumped by every storage action so the presented sheet re-reads the
    /// real stores. Pins, the queue and the quota policy live in SQLite,
    /// not in an observable view model, so nothing else would invalidate
    /// the sheet's body.
    @State private var storageRevision = 0

    /// The app-wide surfaces reached from the labeled command bar rather than the
    /// source list. The sidebar's section order is a frozen navigation
    /// contract (D-14), so a surface that is about the app as a whole —
    /// the adapter, the download queue, the cache — is a command-bar
    /// affordance instead of a ninth source-list row.
    enum ShellSurface: String, Identifiable, CaseIterable {
        case adapter
        case downloads
        case storage

        var id: String { rawValue }
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
        case .adapter: return "Adapter"
        case .downloads: return "Downloads"
        case .storage: return "Storage"
        }
    }

    static func surfaceIdentifier(for surface: ShellSurface) -> String {
        switch surface {
        case .adapter: return AccessibilityIdentifiers.Surface.adapter
        case .downloads: return AccessibilityIdentifiers.Surface.downloads
        case .storage: return AccessibilityIdentifiers.Surface.storage
        }
    }

    private var library: LibraryViewModel { environment.libraryViewModel }

    /// Curation rows reference an asset set id; the shelves need the
    /// catalogue entry behind it to render a title. Built once per body
    /// evaluation from the already-local catalogue — no query.
    private var catalogueByAssetSetID: [String: CatalogueEntry] {
        Dictionary(library.catalogue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                nonEmptySystemIDs: library.nonEmptySystemIDs,
                hasUnidentified: library.hasUnidentifiedEntries,
                selection: $selection
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                libraryCommandBar
                Text(Self.title(for: selection ?? .home))
                    .font(.psHeading)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $presentedSurface) { surface in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                surfaceContent(surface)
                HStack {
                    Spacer()
                    Button("Done") { presentedSurface = nil }
                        .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.done)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
            .environment(environment)
            .frame(minWidth: 560, minHeight: 380)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.title(for: surface))
            .accessibilityIdentifier(Self.surfaceIdentifier(for: surface))
            .onExitCommand { presentedSurface = nil }
        }
        .onChange(of: presentedSurface) { previous, current in
            guard current == nil, let previous else { return }
            focusedShellControl = previous
        }
        .sheet(item: $presentedReadinessEntry) { entry in
            ReadinessSheetView(
                entry: entry,
                report: environment.readinessReport(for: entry),
                onRefresh: {},
                onDownload: { presentedReadinessEntry = nil },
                onPlay: { presentedReadinessEntry = nil },
                onClose: { presentedReadinessEntry = nil }
            )
            .environment(environment)
            .onExitCommand { presentedReadinessEntry = nil }
        }
        .task {
            // The window renders from the local mirror first (LIBR-01's
            // browse-before-download contract); the network pass is a
            // refresh, never a gate.
            library.refresh()
            environment.refreshCurationViewModels()
            await environment.syncNow()
        }
    }

    /// A normal in-window command group avoids the unlabeled system Touch Bar
    /// node produced by SwiftUI's macOS toolbar bridge while keeping the three
    /// app-wide destinations visible and keyboard reachable. Focus is owned by
    /// this composition root so dismissing a sheet can deterministically return
    /// it to the exact command that opened the sheet.
    private var libraryCommandBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            shellCommandButton(.downloads, accessibilityLabel: "Download queue")
            shellCommandButton(.storage, accessibilityLabel: "Storage and quota settings")
            shellCommandButton(.adapter, accessibilityLabel: "Adapter setup")
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library actions")
    }

    private func shellCommandButton(
        _ surface: ShellSurface,
        accessibilityLabel: String
    ) -> some View {
        Button(Self.title(for: surface)) {
            focusedShellControl = surface
            presentedSurface = surface
        }
        .focused($focusedShellControl, equals: surface)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(controlIdentifier(for: surface))
        .overlay {
            RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                .opacity(PlaysteadFocusRing.opacity(isFocused: focusedShellControl == surface))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func controlIdentifier(for surface: ShellSurface) -> String {
        switch surface {
        case .adapter: return AccessibilityIdentifiers.Control.openAdapter
        case .downloads: return AccessibilityIdentifiers.Control.openDownloads
        case .storage: return AccessibilityIdentifiers.Control.openStorage
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
        case .adapter:
            AdapterSetupView()

        case .downloads:
            // The queue path's counterpart to the row path's reclaim
            // prompt: when the scheduler refuses an item on capacity,
            // the reason has to be visible somewhere the user can act
            // on it, or the item just silently stops.
            if let blocked = environment.lastBlockedDownload {
                Text(blocked.reason)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .accessibilityLabel("Download paused: \(blocked.reason)")
                Button("Free up space…") { presentedSurface = .storage }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            DownloadsView(
                rows: environment.downloadRows(),
                onPause: { environment.pauseDownload(id: $0); storageRevision += 1 },
                onResume: { environment.resumeDownload(id: $0); storageRevision += 1 },
                onCancel: { environment.cancelDownload(id: $0); storageRevision += 1 },
                onMoveUp: { environment.moveDownloadUp(id: $0); storageRevision += 1 },
                onMoveDown: { environment.moveDownloadDown(id: $0); storageRevision += 1 }
            )
            .task { await environment.startDownloadQueue() }

        case .storage:
            let snapshot = environment.storageSnapshot()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
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
                        onRemoveQuarantined: { environment.removeQuarantinedPartial(atPath: $0); storageRevision += 1 }
                    )
                }
            }
        }
    }

    /// The navigation title for each section — a pure function so a test
    /// can assert every section actually routes somewhere rather than
    /// falling through to a blank pane.
    static func title(for section: SidebarSection) -> String {
        switch section {
        case .home: return "Library"
        case .continuePlaying: return "Continue"
        case .favorites: return "Favorites"
        case .collections: return "Collections"
        case .queue: return "Queue"
        case .recent: return "Recent"
        case .system(let id): return SystemRegistry.entry(for: id).displayName
        case .unidentified: return "Unidentified"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            homeLibrary
        case .continuePlaying:
            ScrollView { ContinueShelfView(viewModel: environment.continueViewModel, catalogueByAssetSetID: catalogueByAssetSetID) }
        case .favorites:
            ScrollView { FavoritesShelfView(viewModel: environment.favoritesViewModel, catalogueByAssetSetID: catalogueByAssetSetID) }
                .accessibilityIdentifier(AccessibilityIdentifiers.Surface.gameCard)
        case .collections:
            collectionsDetail
        case .queue:
            QueueShelfView(viewModel: environment.queueViewModel, catalogueByAssetSetID: catalogueByAssetSetID)
        case .recent:
            ScrollView { RecentShelfView(viewModel: environment.recentViewModel, catalogueByAssetSetID: catalogueByAssetSetID) }
        case .system(let id):
            catalogueList(library.catalogue(forSystemID: id))
        case .unidentified:
            catalogueList(library.unidentifiedCatalogue)
        }
    }

    private var homeLibrary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Group {
                SearchField(text: Binding(
                    get: { searchText },
                    set: { value in
                        searchText = value
                        library.searchTerm = value
                    }
                ))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library search")
            .accessibilityIdentifier(AccessibilityIdentifiers.Surface.search)

            Group {
                FilterChipRow(
                    chips: library.nonEmptySystemIDs.sorted().map {
                        FilterChip(id: $0, label: SystemRegistry.entry(for: $0).displayName)
                    },
                    selectedID: library.selectedSystemID,
                    onSelect: { library.selectedSystemID = $0 }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library filters")
            .accessibilityIdentifier(AccessibilityIdentifiers.Surface.filter)

            HStack {
                Button("Cards") { libraryLayout = .cards }
                    .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.showCards)
                Button("List") { libraryLayout = .list }
                    .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.showList)
                if let entry = library.filteredCatalogue.first {
                    Button("Check readiness") { presentedReadinessEntry = entry }
                        .accessibilityLabel("Check launch readiness")
                        .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.openReadiness)
                }
            }

            switch libraryLayout {
            case .cards:
                ScrollView {
                    ShelfView(
                        heading: "All games",
                        items: library.filteredCatalogue.map {
                            ShelfItem(
                                id: $0.id,
                                title: $0.displayTitle,
                                systemID: $0.system,
                                isUnidentified: LibraryViewModel.isUnidentified($0),
                                statuses: [.serverOnly]
                            )
                        },
                        layout: .grid,
                        emptyExplanation: "No games match the current search and filters."
                    )
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Game cards")
                .accessibilityIdentifier(AccessibilityIdentifiers.Surface.gameCard)
            case .list:
                Group { catalogueList(library.filteredCatalogue) }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Game list")
                    .accessibilityIdentifier(AccessibilityIdentifiers.Surface.gameList)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.library)
    }

    /// Collections list and, once one is picked, that collection's
    /// members — `CollectionDetailView` needs a selected collection id,
    /// and `CollectionsView` publishes it through a binding.
    private var collectionsDetail: some View {
        HSplitView {
            CollectionsView(
                viewModel: environment.collectionsViewModel,
                selectedCollectionID: $selectedCollectionID
            )
            .frame(minWidth: 260)

            Group {
                if let selectedCollectionID {
                    CollectionDetailView(
                        viewModel: environment.collectionsViewModel,
                        collectionID: selectedCollectionID,
                        catalogueByAssetSetID: catalogueByAssetSetID
                    )
                } else {
                    Text("Select a collection to see what's in it.")
                        .font(.psBody)
                        .foregroundStyle(DesignTokens.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private func catalogueList(_ entries: [CatalogueEntry]) -> some View {
        List(entries) { entry in
            GameRowView(entry: entry)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No games yet",
                    systemImage: "square.stack.3d.up",
                    description: Text(refreshError ?? "Pair with your Playstead server to see your library.")
                )
            }
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
