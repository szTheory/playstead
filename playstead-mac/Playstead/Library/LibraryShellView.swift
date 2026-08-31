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
    /// Bumped by every storage action so the presented sheet re-reads the
    /// real stores. Pins, the queue and the quota policy live in SQLite,
    /// not in an observable view model, so nothing else would invalidate
    /// the sheet's body.
    @State private var storageRevision = 0

    /// The app-wide surfaces reached from the toolbar rather than the
    /// source list. The sidebar's section order is a frozen navigation
    /// contract (D-14), so a surface that is about the app as a whole —
    /// the adapter, the download queue, the cache — is a toolbar
    /// affordance instead of a ninth source-list row.
    enum ShellSurface: String, Identifiable, CaseIterable {
        case adapter
        case downloads
        case storage

        var id: String { rawValue }
    }

    /// The toolbar label and sheet title for each surface — a pure
    /// function, so a test can assert every surface actually routes
    /// somewhere rather than opening a blank sheet.
    static func title(for surface: ShellSurface) -> String {
        switch surface {
        case .adapter: return "Adapter"
        case .downloads: return "Downloads"
        case .storage: return "Storage"
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
            detail
                .navigationTitle(Self.title(for: selection ?? .home))
        }
        .toolbar {
            // Each app-wide surface's own entry point, independent of any
            // one title's row. `DownloadsView`, `StorageView` and
            // `QuotaSettingsView` had no reachable call site at all
            // before these buttons existed.
            ToolbarItem {
                Button(Self.title(for: .downloads)) { presentedSurface = .downloads }
                    .accessibilityLabel("Download queue")
            }
            ToolbarItem {
                Button(Self.title(for: .storage)) { presentedSurface = .storage }
                    .accessibilityLabel("Storage and quota settings")
            }
            ToolbarItem {
                Button(Self.title(for: .adapter)) { presentedSurface = .adapter }
                    .accessibilityLabel("Adapter setup")
            }
        }
        .sheet(item: $presentedSurface) { surface in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                surfaceContent(surface)
                HStack {
                    Spacer()
                    Button("Done") { presentedSurface = nil }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
            .environment(environment)
            .frame(minWidth: 560, minHeight: 380)
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

    /// Each toolbar surface's real content. Every value handed to these
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
            catalogueList(library.catalogue)
        case .continuePlaying:
            ScrollView { ContinueShelfView(viewModel: environment.continueViewModel, catalogueByAssetSetID: catalogueByAssetSetID) }
        case .favorites:
            ScrollView { FavoritesShelfView(viewModel: environment.favoritesViewModel, catalogueByAssetSetID: catalogueByAssetSetID) }
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
        guard let client = apiClient else { return nil }
        let hasCredential = await client.credential != nil
        return hasCredential ? client : nil
    }
}
