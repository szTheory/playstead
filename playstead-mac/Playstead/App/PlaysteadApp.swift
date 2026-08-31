import SwiftUI

/// App entry point. SwiftUI lifecycle, macOS 14.0 deployment target.
///
/// Boots the local SQLite store, then presents the library shell. No
/// network request is required to render the window — `LibraryShellView`
/// reads whatever the local mirror already has (LIBR-01's "browse before
/// download" contract) and refreshes it from `/api/v1/snapshot` in the
/// background once the credential is available.
@main
struct PlaysteadApp: App {
    @State private var appEnvironment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryShellView()
                .environment(appEnvironment)
                .frame(minWidth: 960, minHeight: 560)
        }
        .windowResizability(.contentSize)
        // Becoming active is one of `OutboxWorker`'s three drain triggers
        // (the other two — after every enqueue, and on reachability being
        // regained — are wired inside `AppEnvironment.init`). Without this
        // one, intents enqueued while the app sat in the background after a
        // failed attempt would wait for the user's next mutation.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appEnvironment.applicationDidBecomeActive()
        }
    }
}

/// Shared, observable app-wide dependencies constructed once at launch.
/// Kept intentionally small in this tracer plan: a local store, an API
/// client (always constructed; pairing state itself is tracked
/// internally by `APIClient`, which surfaces `.notPaired` from its own
/// request methods until a credential exists), the cache/download/
/// preflight layer, and the adapter host once the pin loads.
@MainActor
@Observable
final class AppEnvironment {
    let appPaths: AppPaths
    let localStore: LocalStore
    let casManager: CASManager
    let preflightChecker: PreflightChecker
    let launchMaterializer: LaunchMaterializer
    /// Constructed here — not lazily inside a settings view — so a
    /// controller connected before the window opens is already known
    /// the instant any surface reads it (plan 03-10, D-14).
    let controllerHost = ControllerHost()
    let controllerMappingStore: ControllerMappingStore
    /// Holds whatever BIOS a user has validated per system, so a launch
    /// can inject it into the emulator's arguments (plan 03-09/03-10,
    /// P2-CR-002). `references` starts empty — this client has no
    /// confirmed reference BIOS digest yet (see `BiosStore`'s own doc
    /// comment); until one is gathered, every candidate is correctly and
    /// honestly rejected, which is the documented safe default, not a
    /// stub.
    let biosStore: BiosStore
    /// Constructed here for the same reason `controllerHost` is —
    /// reduced-motion state must be known from the first frame, not
    /// discovered lazily by whichever view happens to render first.
    let motionPreference = MotionPreference()
    private(set) var apiClient: APIClient?
    private(set) var adapterHost: AdapterHost?
    private(set) var adapterPinLoadError: Error?

    // MARK: - Curation / sync composition root
    //
    // Every one of these is constructed exactly once, here, and handed to
    // every view model below. Before this, `Outbox`/`OutboxWorker`/
    // `SyncEngine` were only ever constructed inside tests, so the whole
    // curation slice was unreachable from the shipped app (P4-WR-003).
    // The single-instance rule is load-bearing, not stylistic: all five
    // curation nouns must read and write *one* store and *one* outbox, or
    // a favorite added on Home would be invisible on the Favorites shelf
    // and its intent would never drain.

    let catalogueStore: CatalogueStore
    let curationStore: CurationStore
    let cursorStore: CursorStore
    let outbox: Outbox
    let syncEngine: SyncEngine
    let outboxWorker: OutboxWorker
    /// The one place drains are started from — see `OutboxDrainTrigger`.
    let drainTrigger: OutboxDrainTrigger
    let playSessionRecorder: PlaySessionRecorder
    let reachability: Reachability

    let libraryViewModel: LibraryViewModel
    let favoritesViewModel: FavoritesViewModel
    let queueViewModel: QueueViewModel
    let collectionsViewModel: CollectionsViewModel
    let continueViewModel: ContinueViewModel
    let recentViewModel: RecentViewModel

    /// The `Reachability.onChange` registration token, released in
    /// `deinit` — `onChange` now returns a token precisely so a
    /// subscriber can unregister instead of leaking a retained closure.
    /// `nonisolated let` so `deinit` (which is not main-actor isolated)
    /// can actually read it.
    private nonisolated let reachabilityToken: UUID

    /// `paths`, `apiClient`, and `reachability` are injectable purely so a
    /// test can assemble the *real* composition root against a temporary
    /// directory, a stubbed `URLProtocol`, and a `Reachability` it can
    /// drive by hand. Production calls `AppEnvironment()` and gets exactly
    /// what it always did.
    init(
        paths: AppPaths = AppPaths(),
        apiClient: APIClient? = nil,
        reachability: Reachability = Reachability()
    ) {
        self.appPaths = paths
        let store = (try? LocalStore(paths: paths)) ?? LocalStore.inMemoryFallback()
        self.localStore = store
        self.controllerMappingStore = ControllerMappingStore(localStore: store)
        self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: [])
        let client = apiClient ?? APIClient(keychain: KeychainStore())
        self.apiClient = client
        self.reachability = reachability

        let catalogueStore = CatalogueStore(localStore: store)
        let curationStore = CurationStore(localStore: store)
        let outbox = Outbox(localStore: store, curationStore: curationStore)
        let syncEngine = SyncEngine(apiClient: client, localStore: store)
        let recorder = PlaySessionRecorder(localStore: store, curationStore: curationStore, outbox: outbox)
        // `onEntryDelivered`/`onDestructiveRejection` are wired exactly as
        // `OutboxWorker`'s own doc comments specify: a delivered play
        // session marks its `play_sessions_pending` row delivered (that
        // table outlives the outbox row), and a permanently-rejected
        // delete/remove-shaped intent forces a full resync so the row the
        // server never actually deleted is restored rather than left as a
        // silent local tombstone (P4-CR-002).
        let worker = OutboxWorker(
            apiClient: client,
            outbox: outbox,
            onEntryDelivered: { intent in
                if case .playSessionRecord(let sessionID, _, _, _) = intent {
                    recorder.markDelivered(sessionID)
                }
            },
            onDestructiveRejection: { Task { await syncEngine.forceFullResync() } }
        )

        self.catalogueStore = catalogueStore
        self.curationStore = curationStore
        self.cursorStore = CursorStore(localStore: store)
        self.outbox = outbox
        self.syncEngine = syncEngine
        self.outboxWorker = worker
        self.playSessionRecorder = recorder

        self.libraryViewModel = LibraryViewModel(
            catalogueStore: catalogueStore, curationStore: curationStore, syncEngine: syncEngine
        )
        self.favoritesViewModel = FavoritesViewModel(curationStore: curationStore, outbox: outbox)
        self.queueViewModel = QueueViewModel(curationStore: curationStore, outbox: outbox)
        self.collectionsViewModel = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        self.continueViewModel = ContinueViewModel(curationStore: curationStore, outbox: outbox)
        self.recentViewModel = RecentViewModel(curationStore: curationStore, sessionRecorder: recorder)

        let cas = CASManager(paths: paths)
        self.casManager = cas
        self.preflightChecker = PreflightChecker(cas: cas)
        self.launchMaterializer = LaunchMaterializer(paths: paths, cas: cas)

        do {
            let pin = try AdapterPin.load()
            self.adapterHost = AdapterHost(pin: pin, emulatorsRoot: paths.emulators)
        } catch {
            self.adapterPinLoadError = error
        }

        // Drain trigger 1/3: after every `Outbox.enqueue`. Fires on
        // whatever thread enqueued; `OutboxDrainTrigger` is `Sendable`
        // precisely so this closure captures it and not the `@MainActor`
        // environment.
        let trigger = OutboxDrainTrigger(worker: worker)
        self.drainTrigger = trigger
        outbox.onEnqueue = { trigger.fire() }
        // Drain trigger 2/3: reachability regained. `onChange` hands back
        // a token so this observer can actually be removed (`deinit`)
        // instead of outliving the environment.
        self.reachabilityToken = reachability.onChange { isOnline in
            guard isOnline else { return }
            trigger.fire()
        }

        // Wires ControllerHost's connect/disconnect/assign transitions to
        // AdapterHost's launch arguments — without this, a remap or a
        // reconnect never reaches the emulator (P2-CR-003).
        controllerHost.onAssignmentChanged = { [weak self] in self?.refreshActiveControllerMapping() }
        // A controller already connected before the window opens (D-14)
        // must have its mapping applied immediately, not only on the next
        // connect/disconnect/assign transition.
        refreshActiveControllerMapping()
    }

    deinit {
        reachability.removeObserver(reachabilityToken)
    }

    /// Drain trigger 3/3, called from `PlaysteadApp`'s `scenePhase`
    /// observer. Also re-reads the local model, since a background stretch
    /// may have applied journal entries.
    func applicationDidBecomeActive() {
        drainOutbox()
        refreshCurationViewModels()
    }

    /// Starts one `OutboxWorker.drainOnce()` pass and records the `Task`
    /// so callers (and tests) can await the drain that a trigger actually
    /// started. The worker is an actor, so overlapping calls serialize
    /// rather than racing the same entry.
    @discardableResult
    func drainOutbox() -> Task<OutboxDrainResult, Never> {
        drainTrigger.fire()
    }

    /// The favorite toggle behind every library row's Favorite button.
    /// Lives here, not in the view, so the exact code path a click runs is
    /// directly assertable — the reachability gap this whole wiring exists
    /// to close was precisely a path that only tests ever exercised.
    func toggleFavorite(assetSetID: String) {
        favoritesViewModel.toggleFavorite(assetSetID: assetSetID)
        refreshCurationViewModels()
    }

    var isFavorited: (String) -> Bool {
        { [favoritesViewModel] in favoritesViewModel.isFavorited(assetSetID: $0) }
    }

    /// The queue add/remove behind every library row's Queue button.
    @discardableResult
    func toggleQueued(assetSetID: String) -> Bool {
        let changed = queueViewModel.isQueued(assetSetID: assetSetID)
            ? queueViewModel.dequeue(assetSetID: assetSetID)
            : queueViewModel.enqueue(assetSetID: assetSetID)
        refreshCurationViewModels()
        return changed
    }

    /// Re-reads every curation view model from the shared `CurationStore`
    /// — used after a sync pass or a mutation that can affect more than
    /// the shelf the user acted on (favoriting from Home must show up on
    /// the Favorites shelf, a play session must show up in Continue and
    /// Recent).
    func refreshCurationViewModels() {
        favoritesViewModel.refresh()
        queueViewModel.refresh()
        collectionsViewModel.refresh()
        continueViewModel.refresh()
        recentViewModel.refresh()
        libraryViewModel.refresh()
    }

    /// One sync pass, sequenced per this phase's decision: `SnapshotClient`
    /// owns the very first bootstrap (nothing local and no stored cursor),
    /// and `SyncEngine.syncNow()` owns every refresh after that, resuming
    /// from the cursor it stores. The two paths are mutually exclusive by
    /// construction — they must never run concurrently against the same
    /// stores, which is why this is one `await`-ordered function rather
    /// than two independent `.task` modifiers.
    func syncNow() async {
        guard let client = await apiClientIfAvailable() else { return }

        if cursorStore.load() == nil && catalogueStore.count() == 0 {
            let snapshot = SnapshotClient(apiClient: client, localStore: localStore)
            _ = try? await snapshot.fetch()
        } else {
            await syncEngine.syncNow()
        }

        refreshCurationViewModels()
        await libraryViewModel.refreshSyncState()
        // A sync pass is also the natural moment to flush anything the
        // outbox is still holding.
        drainOutbox()
    }

    /// Loads (or lazily creates) the currently assigned controller's
    /// mapping and injects it into `adapterHost` — called whenever the
    /// assigned controller or its mapping changes, and once at launch
    /// if a controller is already connected. A mapping the emulator
    /// never reads would look correct in settings and do nothing in the
    /// game (plan 03-10's own warning), so this is the one place that
    /// connects `ControllerHost`'s assignment to `AdapterHost`'s launch
    /// arguments.
    func refreshActiveControllerMapping() {
        guard case .connected(let descriptor) = controllerHost.connectionState else {
            Task { await adapterHost?.setControllerMapping(nil) }
            return
        }
        let mapping = controllerMappingStore.mapping(forControllerProductID: descriptor.id)
        Task { await adapterHost?.setControllerMapping(mapping) }
    }

    func makeDownloadEngine() -> DownloadEngine {
        DownloadEngine(session: URLSession(configuration: .ephemeral), paths: appPaths, cas: casManager)
    }
}
