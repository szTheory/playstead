import SwiftUI
import AppKit

/// App entry point. SwiftUI lifecycle, macOS 14.0 deployment target.
///
/// Boots the local SQLite store, then presents the library shell. No
/// network request is required to render the window — `LibraryShellView`
/// reads whatever the local mirror already has (LIBR-01's "browse before
/// download" contract) and refreshes it from `/api/v1/snapshot` in the
/// background once the credential is available.
@main
struct PlaysteadApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
#if UI_TESTING
            if XCTestHostBootstrap.isRequested() {
                XCTestHostInertRootView()
            } else if UITestBootstrap.isRequested() {
                UITestProfileRootView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON"] == "1" {
                ConflictComparisonHarnessRootView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION"] != nil {
                OnlyCopyInterruptionHarnessRootView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_ONLY_COPY_NEUTRAL"] == "1" {
                OnlyCopyInterruptionNeutralHarnessRootView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] == "1" {
                HostedRunnerLaunchCanaryView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] == "1" {
                HostedRunnerFocusCanaryView()
            } else {
                ProductionRootView()
            }
#else
            if XCTestHostBootstrap.isRequested() {
                XCTestHostInertRootView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] == "1" {
                HostedRunnerLaunchCanaryView()
            } else if ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] == "1" {
                HostedRunnerFocusCanaryView()
            } else {
                ProductionRootView()
            }
#endif
#else
            ProductionRootView()
#endif
        }
        .windowResizability(.contentSize)
    }
}

#if UI_TESTING
/// The real library shell backed by one validated, isolated production-store profile.
private struct UITestProfileRootView: View {
    @State private var session: UITestProfileSession

    init() {
        do {
            _session = State(initialValue: try UITestBootstrap.makeSession())
        } catch {
            fatalError("UI-testing bootstrap failed closed: \(error)")
        }
    }

    var body: some View {
        LibraryShellView()
            .environment(session.environment)
            .frame(minWidth: 960, minHeight: 560)
    }
}
#endif

/// Owns production dependencies only when the production root is selected.
///
/// Keeping `AppEnvironment` out of `PlaysteadApp` is security-significant for
/// compile-gated hosted canaries: constructing the normal environment creates
/// an `APIClient` whose credential checks correctly consult the login Keychain.
/// A launch-mechanism canary must never touch that user-owned store.
private struct ProductionRootView: View {
    @State private var appEnvironment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LibraryShellView()
            .environment(appEnvironment)
            .frame(minWidth: 960, minHeight: 560)
            // D-07 crash recovery, once per launch: a session Playstead
            // died in the middle of (emulator exited, promotion never
            // ran) is replayed through the same settle-then-promote
            // pass a live session runs. Before this call site existed,
            // `SaveSessionRecovery` was never constructed in production
            // at all (WINDOWS #46) — its own doc comment described the
            // caller this is.
            .task { await appEnvironment.recoverAbandonedSaveSessionsAtLaunch() }
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

#if DEBUG
/// Explicit app-host mode for Unit and Rendering test plans.
///
/// XCTest may launch the host application even when a test never asks for a
/// window. That process must not fall through to `ProductionRootView`, whose
/// credential client correctly consults the login Keychain. The test plans
/// opt into this inert root with one finite value; UI and LiveServer plans do
/// not set it because they own their own isolated launch composition.
private enum XCTestHostBootstrap {
    static let modeKey = "PLAYSTEAD_XCTEST_HOST_MODE"

    static func isRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[modeKey] == "inert"
    }
}

private struct XCTestHostInertRootView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}

/// Minimal no-dependency window used to prove ad-hoc launch on hosted runners.
///
/// This branch deliberately constructs no `AppEnvironment`, `APIClient`, or
/// `KeychainStore`, so it cannot inspect the developer's login Keychain or
/// trigger an authorization prompt during local verification.
private struct HostedRunnerLaunchCanaryView: View {
    var body: some View {
        Text("Playstead launch canary")
            .accessibilityIdentifier("ci.canary.launch.ready")
            .padding()
            .frame(minWidth: 420, minHeight: 180)
    }
}

/// Minimal live focus surface for the hosted-runner adoption gate.
///
/// The full library shell intentionally contains multiple focus roles and is
/// covered by the exhaustive screen inventory later in Phase 3.5. This
/// compilation-gated surface isolates the runner mechanism so the Wave 0
/// canary can prove exact Tab/Shift-Tab order, wrap, ownership, and Space
/// activation without coupling that proof to unrelated application topology.
private struct HostedRunnerFocusCanaryView: View {
    @State private var isPresented = false

    var body: some View {
        HStack {
            Button("Downloads") { isPresented = true }
                .accessibilityLabel("Download queue")
            Button("Storage") { isPresented = true }
                .accessibilityLabel("Storage and quota settings")
            Button("Adapter") { isPresented = true }
                .accessibilityLabel("Adapter setup")
        }
        .padding()
        .frame(minWidth: 420, minHeight: 180)
        .sheet(isPresented: $isPresented) {
            VStack {
                Text("Keyboard activation succeeded")
                Button("Done") { isPresented = false }
            }
            .padding()
            .frame(minWidth: 320, minHeight: 160)
        }
    }
}
#endif

/// Shared, observable app-wide dependencies constructed once at launch.
/// Kept intentionally small in this tracer plan: a local store, an API
/// client (always constructed; pairing state itself is tracked
/// internally by `APIClient`, which surfaces `.notPaired` from its own
/// request methods until a credential exists), the cache/download/
/// preflight layer, and the adapter host once the pin loads.
/// Where the adapter install surface currently is. `.failed` always
/// carries a real, specific reason — a surface that says "failed" with
/// nothing actionable is the failure mode this whole slice exists to
/// correct.
enum AdapterSetupPhase: Equatable {
    case idle
    case installing
    case failed(String)
}

@MainActor
@Observable
final class AppEnvironment {
    let appPaths: AppPaths
    let localStore: LocalStore
    let casManager: CASManager
    let preflightChecker: PreflightChecker
    /// The persistent download queue `ReadinessEngine` enqueues a
    /// replacement into when it finds a corrupted cache object. Shared,
    /// like every other store here, so a requeue made during a readiness
    /// evaluation is the same queue the rest of the app reads.
    let downloadQueue: DownloadQueue
    /// Pins, quota policy and reclaim planning — the download-management
    /// layer. Every one of these was previously constructed only inside
    /// its own unit test, so the shipped app enforced no quota at all and
    /// `DownloadsView`/`StorageView`/`QuotaSettingsView`/
    /// `ReclaimPromptView` had no reachable call site. They are shared
    /// instances for the same reason the curation stores are: the pin a
    /// row sets must be the pin `EvictionPlanner` excludes and the pin
    /// `DownloadCoordinator` prioritises.
    let pinStore: PinStore
    let quotaManager: QuotaManager
    let evictionPlanner: EvictionPlanner
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
#if UI_TESTING
    /// Set before a deterministic profile shell renders. This prevents the
    /// background sync and download paths from consulting any Keychain or network.
    private(set) var uiTestingBlocksExternalIO = false
    /// MC-02 test-only observability: every URL `openConsoleSavesExport`
    /// resolved and would have opened. `NSWorkspace.shared.open` is
    /// legitimately skipped under `UI_TESTING` (a real browser must never
    /// launch during automated tests), which would otherwise leave no
    /// observable trace that the default "Export saves…" button performs
    /// a real action rather than a bare dismissal -- the exact shape of
    /// the shipped MC-02 defect. A front-door journey reads this list,
    /// never a routing flag.
    private(set) var uiTestConsoleExportAttempts: [String] = []
#endif
    private(set) var adapterHost: AdapterHost?
    private(set) var adapterPinLoadError: Error?

    // MARK: - Adapter install surface
    //
    // Before this, `AdapterInstaller` was referenced only from its own
    // test file and `AdapterHost.setInstallState` had no production
    // caller at all, so `installState` was permanently `.notInstalled`
    // in the shipped app and no user could ever install the emulator.
    // `AdapterSetupView` is the reachable surface; everything it does
    // goes through the properties and methods below.

    private(set) var adapterCatalog: AdapterCatalog?
    private(set) var adapterInstaller: AdapterInstaller?
    /// What the app currently believes about the installed adapter —
    /// restored from the recorded installation at launch, updated by
    /// every install/select, and read by both `ReadinessEngine`'s
    /// emulator check and the capability card.
    private(set) var adapterInstallState: AdapterInstallState = .notInstalled
    private(set) var adapterProvenance: AdapterProvenance = .pinnedRelease
    private(set) var adapterSetupPhase: AdapterSetupPhase = .idle

    // MARK: - Download coordination
    //
    // `DownloadCoordinator` needs a paired credential (for the blob base
    // URL and the bearer token) that does not exist at launch on a fresh
    // install, so it is built on first use rather than in `init` — but
    // built exactly once, and stored here, so the whole app drives one
    // scheduler over one queue.

    private(set) var downloadCoordinator: DownloadCoordinator?
    /// Live transfer progress per asset set, republished from the
    /// coordinator's event stream so `DownloadsView` renders real
    /// percentages rather than a placeholder.
    private(set) var downloadProgressByAssetSet: [String: Int] = [:]
    /// The most recent `.blocked` coordinator event, if any — the queue
    /// path's counterpart to the row path's synchronous quota verdict.
    private(set) var lastBlockedDownload: (itemID: String, assetSetID: String, reason: String)?
    /// Injected by tests so the coordinator's transfers go through
    /// `StubURLProtocol` instead of the network. `nil` in production.
    private let downloadSessionOverride: URLSession?

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
    /// The single shared `SaveStore`/`SaveOutbox`/`SaveConflictResolver`
    /// instances every save-safety surface below reads and writes —
    /// before this (MC-01..MC-06), no surface but `SyncEngine`'s own
    /// private journal-apply store and `GameRowView`'s ad hoc
    /// launch-path instance existed, so `ReclaimPromptView`,
    /// `StorageView`, `ReadinessEngine`'s save row, the card's
    /// divergence badge, `OnlyCopyEscalationPanel` and
    /// `ConflictComparisonSheet` had no committed local state to read at
    /// all.
    let saveStore: SaveStore
    let saveOutbox: SaveOutbox
    let saveConflictResolver: SaveConflictResolver
    /// D-31's durable blocked-capture state, shared by every capture
    /// session so a blockage raised by one play session is still open
    /// (and still un-re-alerted) for the next one.
    let saveCaptureBlockedState: SaveCaptureBlockedState
    /// D-07's crash-recovery replay, run once per launch by
    /// `recoverAbandonedSaveSessionsAtLaunch()`. Before 04-19 this type
    /// had no production construction site at all (WINDOWS #46), so a
    /// session interrupted between emulator exit and promotion was
    /// never replayed by the shipped app.
    let saveSessionRecovery: SaveSessionRecovery
    /// D-16/D-32's dedicated upload lane. Constructed eagerly with the
    /// same non-optional client `SyncEngine` and `OutboxWorker` already
    /// take -- the established pattern here for a client-dependent
    /// collaborator. An unpaired client makes `send` throw `.notPaired`
    /// before any connection is opened, which leaves the revision
    /// `queued` and retryable rather than silently dropped (D-32).
    /// Before 04-19 this type was never constructed in production at
    /// all (WINDOWS #44), so nothing a Playstead session captured ever
    /// left the Mac.
    let saveUploadLane: SaveUploadLane
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

    /// Guards `recoverAbandonedSaveSessionsAtLaunch()` so a scene that
    /// re-runs its `.task` never starts a second replay pass. (Replay is
    /// idempotent by digest, so this is an efficiency guard, not a
    /// correctness one.)
    private var hasRecoveredAbandonedSaveSessions = false

    /// `paths`, `apiClient`, and `reachability` are injectable purely so a
    /// test can assemble the *real* composition root against a temporary
    /// directory, a stubbed `URLProtocol`, and a `Reachability` it can
    /// drive by hand. Production calls `AppEnvironment()` and gets exactly
    /// what it always did.
    convenience init(
        paths: AppPaths = AppPaths(),
        apiClient: APIClient? = nil,
        reachability: Reachability = Reachability(),
        downloadSession: URLSession? = nil
    ) {
        let store = (try? LocalStore(paths: paths)) ?? LocalStore.inMemoryFallback()
        let client = apiClient ?? APIClient(keychain: KeychainStore())
        self.init(
            paths: paths,
            openedStore: store,
            apiClient: client,
            reachability: reachability,
            downloadSession: downloadSession
        )
    }

#if UI_TESTING
    convenience init(
        uiTestingPaths paths: AppPaths,
        localStore: LocalStore,
        reachability: Reachability,
        /// A deterministic profile's real, offline, synthetic pairing
        /// credential -- `nil` (the default) keeps every existing
        /// deterministic profile genuinely unpaired. This never opens a
        /// real network connection: `openConsoleSavesExport` itself
        /// never performs a network call, only resolves a URL and, under
        /// `UI_TESTING`, records it for test observability instead of
        /// calling `NSWorkspace.shared.open`. Seeding "this Mac is
        /// already paired" is world state a save-safety journey may
        /// legitimately need, never a routing flag.
        credential: PairingCredential? = nil
    ) {
        self.init(
            paths: paths,
            openedStore: localStore,
            apiClient: credential.map { APIClient(keychain: KeychainStore(), credential: $0) }
                ?? APIClient.unpairedForUITesting(),
            reachability: reachability,
            downloadSession: nil
        )
    }
#endif

    private init(
        paths: AppPaths,
        openedStore store: LocalStore,
        apiClient: APIClient,
        reachability: Reachability,
        downloadSession: URLSession?
    ) {
        self.appPaths = paths
        self.downloadSessionOverride = downloadSession
        self.localStore = store
        self.controllerMappingStore = ControllerMappingStore(localStore: store)
        self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: [])
        let client = apiClient
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

        let saveStore = SaveStore(localStore: store)
        let saveOutbox = SaveOutbox(localStore: store)
        self.saveStore = saveStore
        self.saveOutbox = saveOutbox
        self.saveConflictResolver = SaveConflictResolver(saveStore: saveStore, saveOutbox: saveOutbox)
        self.saveCaptureBlockedState = SaveCaptureBlockedState(localStore: store)
        self.saveSessionRecovery = SaveSessionRecovery(saveStore: saveStore)
        let uploadLane = SaveUploadLane(apiClient: client, saveStore: saveStore)
        self.saveUploadLane = uploadLane

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

        self.downloadQueue = DownloadQueue(localStore: store)

        let pinStore = PinStore(localStore: store)
        self.pinStore = pinStore
        // The cache root is the volume whose free space the floor is
        // measured against — the objects directory, not the app bundle.
        self.quotaManager = QuotaManager(localStore: store, cacheRootURL: paths.objects)
        self.evictionPlanner = EvictionPlanner(
            localStore: store, catalogueStore: catalogueStore, pinStore: pinStore, cas: cas, paths: paths,
            saveStore: saveStore
        )

        do {
            let pin = try AdapterPin.load()
            let host = AdapterHost(pin: pin, emulatorsRoot: paths.emulators)
            self.adapterHost = host
            self.adapterCatalog = AdapterCatalog(pin: pin)
            self.adapterInstaller = AdapterInstaller(
                pin: pin, emulatorsRoot: paths.emulators, localStore: store
            )
            // An install performed in a previous session lives in SQLite
            // and on disk; without restoring it here the app would come
            // back up claiming nothing was ever installed.
            if let recorded = AdapterInstaller.recordedInstallation(pin: pin, localStore: store),
               FileManager.default.fileExists(atPath: recorded.executablePath) {
                self.adapterInstallState = .installed(
                    executablePath: recorded.executablePath, verified: recorded.verified
                )
                self.adapterProvenance = recorded.provenance
                Task { await host.setInstallation(recorded) }
            }
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
            // The save lane drains on the same transition, and ahead of
            // nothing else here -- it is a separate actor, so this does
            // not queue behind the curation outbox (D-32). The lane is
            // captured directly rather than through `self`, which is not
            // yet fully initialized at this point in `init`.
            Task { await uploadLane.drainOnce() }
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

#if UI_TESTING
    func blockExternalIOForUITesting() {
        uiTestingBlocksExternalIO = true
    }

    /// Bounded, synthetic-only acceptance evidence exposed by the
    /// compile-gated UI profile. It contains row IDs, an outbox count and
    /// catalogue member digests only; never filenames, paths, credentials,
    /// payload JSON or user content.
    func curationReorderEvidenceValue(collectionID: String) -> String {
        let order = curationStore.fetchCollectionMembers()
            .filter { $0.collectionID == collectionID }
            .map(\.id)
            .joined(separator: ",")
        let catalogueFingerprint = catalogueStore.fetchAll()
            .flatMap(\.members)
            .compactMap(\.sha256)
            .sorted()
            .joined(separator: ",")
        return "order=\(order);outbox=\(outbox.listAll().count);catalogue=\(catalogueFingerprint)"
    }
#endif

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

    /// Starts one `SaveUploadLane.drainOnce()` pass. The lane is an
    /// actor, so overlapping calls serialize rather than racing the same
    /// revision.
    @discardableResult
    func drainSaveUploads() -> Task<OutboxDrainResult, Never> {
        Task { [saveUploadLane] in await saveUploadLane.drainOnce() }
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

        // One owner for every pass. SyncEngine already bootstraps from the
        // snapshot when no cursor is stored, and its bootstrap is strictly more
        // complete than SnapshotClient's: it applies the curation branch in the
        // same transaction as the catalogue and records the as-of cursor the
        // data reflects. Routing the first pass through SnapshotClient instead
        // left the mirror with no position, so the incremental /changes path
        // stayed unreachable until some later pass happened to run, and the
        // curation rows that snapshot carried were dropped on the floor.
        await syncEngine.syncNow()

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

    // MARK: - Adapter install / select

    /// Downloads and installs the pinned adapter, then hands the
    /// resulting installation — including the executable digest baseline
    /// launch re-hashes against — to `AdapterHost`.
    @discardableResult
    func installAdapter() async -> Bool {
        guard let installer = adapterInstaller else {
            adapterSetupPhase = .failed("No adapter is pinned in this build.")
            return false
        }
        adapterSetupPhase = .installing
        do {
            let installation = try await installer.install()
            await adopt(installation)
            adapterSetupPhase = .idle
            return true
        } catch {
            adapterSetupPhase = .failed(Self.describeInstallFailure(error))
            return false
        }
    }

    /// Registers an application bundle the user already has. No download,
    /// no archive — so nothing is compared against the pin's archive
    /// digest; the selected executable's own digest becomes the baseline
    /// and the capability card says the build was never verified against
    /// the pinned release.
    @discardableResult
    func selectExistingAdapter(appURL: URL) async -> Bool {
        guard let installer = adapterInstaller else {
            adapterSetupPhase = .failed("No adapter is pinned in this build.")
            return false
        }
        do {
            let installation = try await installer.selectExisting(appURL: appURL)
            await adopt(installation)
            adapterSetupPhase = .idle
            return true
        } catch {
            adapterSetupPhase = .failed(Self.describeInstallFailure(error))
            return false
        }
    }

    private func adopt(_ installation: AdapterInstallation) async {
        adapterInstallState = .installed(
            executablePath: installation.executablePath, verified: installation.verified
        )
        adapterProvenance = installation.provenance
        await adapterHost?.setInstallation(installation)
    }

    /// A real reason, never a generic "install failed" — a user who can't
    /// tell a digest mismatch from a network failure can't act on either.
    static func describeInstallFailure(_ error: Error) -> String {
        guard let installError = error as? AdapterInstallError else {
            return "The adapter could not be installed: \(error.localizedDescription)"
        }
        switch installError {
        case .digestMismatch(let expected, let actual):
            return "The downloaded file did not match the pinned release. Expected \(expected), got \(actual). Nothing was installed."
        case .downloadFailed(let reason):
            return "The adapter could not be downloaded (\(reason)). Check your connection and try again."
        case .expansionFailed(let reason):
            return "The downloaded adapter could not be unpacked (\(reason))."
        case .executableNotFound:
            return "That application does not contain the expected program file, so it can't be used as this adapter."
        }
    }

    /// The honest capability card for the current installation, or `nil`
    /// when this build has no pinned adapter to describe at all.
    var adapterCapabilityCard: AdapterCapabilityCard? {
        guard let descriptor = adapterCatalog?.descriptor else { return nil }
        return AdapterCapabilityCard(
            descriptor: descriptor,
            installState: adapterInstallState,
            provenance: adapterProvenance,
            biosStore: biosStore
        )
    }

    // MARK: - Readiness

    /// The app-managed save directory for one asset set.
    ///
    /// The asset set id arrives from the paired server, so it is
    /// validated as a safe bare filename before it becomes a path
    /// component — the same rule `LaunchMaterializer` and `AppPaths`
    /// apply to server-declared names and digests (CR-01/CR-02).
    func saveDirectoryURL(forAssetSetID assetSetID: String) throws -> URL {
        let safe = try PathSafety.validatedFilename(assetSetID)
        return appPaths.root
            .appendingPathComponent("saves", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }

    /// Where one asset set's durable save captures land — deliberately
    /// not the save directory itself, which the adapter's
    /// `artifact_glob` owns. Same server-supplied-id validation rule as
    /// `saveDirectoryURL(forAssetSetID:)` (CR-01/CR-02).
    func saveCaptureDirectoryURL(forAssetSetID assetSetID: String) throws -> URL {
        try SaveCapturePaths.captureDirectory(root: appPaths.root, assetSetID: assetSetID)
    }

    /// A fresh coordinator for one play session (D-04's "exactly one
    /// promoted revision per session" is per-session state, so this is
    /// never a shared singleton). Constructed here rather than in the
    /// view so the shipped Play path and the tested path build the same
    /// object, and so the promotion hook that starts an upload drain is
    /// attached in exactly one place.
    func makeSaveSessionCoordinator() -> SaveSessionCoordinator {
        SaveSessionCoordinator(
            saveStore: saveStore,
            blockedState: saveCaptureBlockedState,
            // Drain trigger: a session's promotion is the moment a new
            // local-only revision exists, and a revision that exists on
            // exactly one device is the most dangerous state in the
            // product (D-32).
            onPromoted: { [saveUploadLane] in Task { await saveUploadLane.drainOnce() } }
        )
    }

    /// D-07's crash recovery, run once per app launch: for every save
    /// line this Mac knows about, replay any session left open (a
    /// `staged` row with no `promoted` row) through the identical
    /// settle-then-promote pass a live session runs at its own end.
    ///
    /// Never fatal and never blocking: a line whose catalogue entry or
    /// save directory cannot be resolved is skipped, and a replay that
    /// throws is skipped. `SaveSessionRecovery.replay` is idempotent by
    /// digest, so running this again (a relaunch, a second call) is
    /// safe and produces nothing new.
    func recoverAbandonedSaveSessionsAtLaunch() async {
        guard !hasRecoveredAbandonedSaveSessions else { return }
        hasRecoveredAbandonedSaveSessions = true

        let entries = catalogueStore.fetchAll()
        var replayedCount = 0

        for lineID in Set(saveStore.fetchAllRevisions().map(\.saveLineID)).sorted() {
            guard
                let line = saveStore.fetchLine(id: lineID),
                let entry = entries.first(where: { Self.saveContentKey(for: $0) == line.contentKey }),
                // The launch path resolves the artifact name from the
                // materialized ROM's own filename; the same declared
                // member name is what materialization produced.
                let romFileName = entry.members.first(where: { $0.sha256 != nil && $0.name != nil })?.name,
                let saveDirectory = try? saveDirectoryURL(forAssetSetID: entry.id),
                let captureDirectory = try? saveCaptureDirectoryURL(forAssetSetID: entry.id)
            else { continue }

            let targetURL = SaveCapturePaths.targetURL(saveDirectory: saveDirectory, romFileName: romFileName)
            do {
                let rows = try await saveSessionRecovery.replayAll(
                    saveLineID: lineID,
                    artifactSource: FileSaveArtifactSource(url: targetURL),
                    destinationDirectory: captureDirectory,
                    artifactRelativePath: targetURL.lastPathComponent
                )
                replayedCount += rows.count
            } catch {
                // Recovery is best-effort by construction: a line that
                // cannot be replayed must never stop the app launching,
                // and the next launch will try again.
                continue
            }
        }

        if replayedCount > 0 {
            refreshCurationViewModels()
        }
        // Launch is also the natural moment to flush anything a previous
        // session captured and never managed to upload.
        drainSaveUploads()
    }

    /// Runs the six real readiness checks for one catalogue entry. This
    /// is the only gate between the user pressing Play and
    /// `AdapterHost.launch` — `ReadinessEngine` was previously
    /// instantiated only in tests, so nothing the shipped app did ever
    /// ran these checks.
    func readinessReport(for entry: CatalogueEntry) -> ReadinessReport {
        guard let saveDirectory = try? saveDirectoryURL(forAssetSetID: entry.id) else {
            return ReadinessReport(checks: [
                ReadinessCheck(
                    kind: .saveDirectory,
                    outcome: .blocked("Playstead can't write this game's saves."),
                    finding: "This title's identifier can't be used as a folder name, so Playstead has nowhere safe to keep its saves.",
                    remedy: Remedy(title: "Repair save folder", action: .repairSaveDirectory)
                )
            ])
        }
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)

        // Every dependency is captured by value: the engine is built
        // fresh per evaluation, and a closure that reached back into
        // main-actor state would make an entirely local, synchronous
        // check depend on actor hopping.
        let installState = adapterInstallState
        let biosRequired = adapterCatalog?.descriptor.biosRequired ?? false
        let hasBIOS = biosStore.hasManagedBIOS(forSystem: entry.system)
        let hasController = controllerHost.hasAnyController
        // MC-04: read once, by value, for the same actor-hopping reason
        // every other dependency above is captured by value.
        let saveState = saveReadinessCase(for: entry)

        let engine = ReadinessEngine(
            cas: casManager,
            downloadQueue: downloadQueue,
            adapterInstallState: { installState },
            biosRequired: biosRequired,
            hasManagedBIOS: { hasBIOS },
            hasController: { hasController },
            saveDirectoryURL: saveDirectory,
            saveReadiness: { saveState }
        )
        return engine.evaluate(
            assetSetID: entry.id, requiredMembers: Self.requiredMembers(of: entry)
        )
    }

    /// The required members of one entry, in `ReadinessEngine`'s own
    /// shape. A member missing a digest or a size can't be checked and
    /// can't be downloaded, so it is not a required member this gate can
    /// speak about.
    static func requiredMembers(of entry: CatalogueEntry) -> [RequiredMember] {
        entry.members.filter(\.required).compactMap { member in
            guard let sha256 = member.sha256, let size = member.size else { return nil }
            return RequiredMember(sha256: sha256, size: size)
        }
    }

    // MARK: - Save state (MC-01..MC-06): the single seam every save-safety
    // surface below reads from `SaveStore`'s committed rows.

    /// The content key a save line is keyed by for `entry` (D-10) — the
    /// ROM's own sha256 when known, exactly matching `GameRowView`'s own
    /// launch-path resolution (`members.first?.sha256 ?? entry.id`),
    /// never `entry.id` alone when a real digest is available.
    static func saveContentKey(for entry: CatalogueEntry) -> String {
        Self.requiredMembers(of: entry).first?.sha256 ?? entry.id
    }

    private func saveLine(for entry: CatalogueEntry) -> SaveLineRow? {
        saveStore.fetchLine(contentKey: Self.saveContentKey(for: entry), saveKind: "battery", slot: "0")
    }

    private func catalogueEntry(assetSetID: String) -> CatalogueEntry? {
        catalogueStore.fetchAll().first { $0.id == assetSetID }
    }

    /// D-40's per-game only-copy input (MC-01): how many of this game's
    /// save revisions are not yet durable anywhere but this Mac, read
    /// from `SaveStore`'s committed `durability` column — never from a
    /// download/upload lane's in-flight, optimistic state. A revision
    /// with an upload queued but not yet confirmed `uploaded` still
    /// counts: `OnlyCopyInterruptiveSheet`'s own doc comment requires
    /// computing this from durable rows, never a pending upload's
    /// assumed outcome, so an upload in flight for this line must not
    /// zero out the count early.
    func onlyOnThisMacCount(forAssetSetID assetSetID: String) -> Int {
        guard let entry = catalogueEntry(assetSetID: assetSetID) else { return 0 }
        return onlyOnThisMacCount(for: entry)
    }

    private func onlyOnThisMacCount(for entry: CatalogueEntry) -> Int {
        guard let line = saveLine(for: entry) else { return 0 }
        return saveStore.fetchRevisions(saveLineID: line.id)
            .filter { $0.durability != SaveDurability.uploaded.rawValue }
            .count
    }

    /// D-38/MC-03: whether `assetSetID`'s save line is a genuine,
    /// undisposed fork right now — the boolean `LibraryStatus
    /// .forSaveState(conflicted:)` unions into the card's rank-1 rung.
    /// Reads `SaveStore` fresh on every call (D-21), never remembered
    /// state.
    func hasUnacknowledgedSaveDivergence(assetSetID: String) -> Bool {
        guard let entry = catalogueEntry(assetSetID: assetSetID), let line = saveLine(for: entry) else { return false }
        let heads = saveStore.fetchHeads(saveLineID: line.id).map(\.id)
        let disposed = saveStore.fetchForkDisposition(saveLineID: line.id)?.headRevisionIDs
        return SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: heads, disposedHeadIDs: disposed)
    }

    /// D-37/MC-04: the real `SaveReadinessCase` for `entry`, computed
    /// from `SaveStore`'s committed heads instead of the engine's
    /// `.noSavesYet` placeholder default. `.serverHasNewer` is
    /// deliberately not produced here — distinguishing it from
    /// `.localOnlyReachable` needs per-device session context this
    /// client doesn't track yet (documented limitation, not a silent
    /// stub: every other real case, including the higher-priority
    /// `.twoVersions` warning D-46 requires never blocks, is computed).
    func saveReadinessCase(for entry: CatalogueEntry) -> SaveReadinessCase {
        guard let line = saveLine(for: entry) else { return .noSavesYet }
        let heads = saveStore.fetchHeads(saveLineID: line.id)
        guard !heads.isEmpty else { return .noSavesYet }
        if SaveStateModel.isConflicted(headRevisionIDs: heads.map(\.id)) {
            return .twoVersions
        }
        guard let head = heads.first else { return .noSavesYet }
        if head.durability == SaveDurability.uploaded.rawValue {
            return .uploadedAndCurrent
        }
        return reachability.isOnline ? .localOnlyReachable : .localOnlyExpectedOffline
    }

    /// D-32/D-40/MC-05: the escalated-tier failure classification this
    /// Mac can currently determine on its own.
    ///
    /// `.offlineQueue` when unreachable, unconditionally and before
    /// anything else is consulted (D-40: an offline queue must never
    /// escalate, whatever the last online attempt happened to fail
    /// with). Otherwise the live lane's own most recent outcome — which
    /// is `.none` while uploads are succeeding, and one of D-40's four
    /// unfixable reasons when the server has actually said so.
    ///
    /// Until 04-19 this returned a constant `.none` for the online case,
    /// because `SaveUploadLane` had no classification output and no
    /// production construction site at all: the four unfixable reasons
    /// were unreachable code in the shipped app (WINDOWS #40, #44).
    func saveUploadFailureClassification() -> SaveUploadFailureClassification {
        guard reachability.isOnline else { return .offlineQueue }
        return saveUploadLane.lastFailureClassification
    }

    /// D-50 through D-55/MC-06: the real `ConflictSide` array for a
    /// diverged game, read from `SaveStore`'s current heads.
    /// Play-time-since-the-split has no client-side computation yet (no
    /// per-device session/fork association exists in this schema), so
    /// every side renders the "No recorded play here" fallback — the
    /// same honest limitation plan 04-10's console comparison panel
    /// documents for the identical reason, not a fabricated number.
    func conflictSides(forAssetSetID assetSetID: String) -> [ConflictSide] {
        guard let entry = catalogueEntry(assetSetID: assetSetID), let line = saveLine(for: entry) else { return [] }
        let heads = saveStore.fetchHeads(saveLineID: line.id)
        let disposition = saveStore.fetchForkDisposition(saveLineID: line.id)
        return heads.map { row in
            ConflictSide(
                id: row.id,
                origin: row.originDeviceID ?? "another device",
                lastSaved: Self.relativeSaveDescription(for: row),
                playTimeSinceSplit: SaveVocabulary.compareSideLine2NoSessions,
                sinceSplitCount: 0,
                hasClockCaveat: false,
                isDownloaded: casManager.contains(row.blobSHA256),
                isChosen: disposition?.action == .choose && disposition?.chosenRevisionID == row.id,
                digest: row.blobSHA256
            )
        }
    }

    private static func relativeSaveDescription(for row: SaveRevisionRow) -> String {
        guard let recordedAt = row.recordedAt, let date = ISO8601DateFormatter().date(from: recordedAt) else {
            return "recently"
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    /// MC-06: "Continue from this one" — the exact `SaveConflictResolver
    /// .chooseSide` call `ConflictComparisonSheet`'s production caller
    /// makes; appends a disposition, never deletes a head (D-48/D-49).
    @discardableResult
    func resolveSaveDivergence(assetSetID: String, chosenRevisionID: String) -> SaveConflictResolution? {
        guard let entry = catalogueEntry(assetSetID: assetSetID), let line = saveLine(for: entry) else { return nil }
        let heads = saveStore.fetchHeads(saveLineID: line.id).map(\.id)
        return try? saveConflictResolver.chooseSide(
            saveLineID: line.id, chosenRevisionID: chosenRevisionID, headRevisionIDs: heads,
            originName: { [saveStore] id in saveStore.fetchRevision(id: id)?.originDeviceID ?? "another device" }
        )
    }

    /// MC-06: "Keep both" — the exact `SaveConflictResolver.keepBoth`
    /// call; every head stays standing, and the fork is marked disposed
    /// so it is never re-raised for this exact head set (D-52).
    @discardableResult
    func acknowledgeSaveDivergence(assetSetID: String, thisDeviceOrigin: String) -> SaveConflictResolution? {
        guard let entry = catalogueEntry(assetSetID: assetSetID), let line = saveLine(for: entry) else { return nil }
        let heads = saveStore.fetchHeads(saveLineID: line.id).map(\.id)
        return try? saveConflictResolver.keepBoth(
            saveLineID: line.id, headRevisionIDs: heads, thisDeviceOrigin: thisDeviceOrigin
        )
    }

    /// MC-02's escape hatch: the console's saves-scope export surface
    /// (plan 04-10's `/saves/:id` `SavesLive`) for the game's own save
    /// line — pure, so a test can assert the exact destination with no
    /// `NSWorkspace` side effect. `nil` when unpaired or no save line
    /// has been committed for this game yet.
    func consoleSavesExportURL(forAssetSetID assetSetID: String, baseURL: URL) -> URL? {
        guard let entry = catalogueEntry(assetSetID: assetSetID), let line = saveLine(for: entry) else { return nil }
        return baseURL.appendingPathComponent("saves").appendingPathComponent(line.id)
    }

    /// MC-02: opens the real escape hatch in the user's browser. Never a
    /// second export mechanism — this reuses plan 04-10's `/saves/:id`
    /// page exactly as `OnlyCopyEscalation`'s own "Export saves…"
    /// control is meant to. Narrowed to the first affected game per
    /// D-62 (no per-revision/bulk export target exists in the shipped
    /// `Export.SavesPlan` pipeline yet — see 04-10-SUMMARY.md).
    func openConsoleSavesExport(forAssetSetIDs assetSetIDs: Set<String>) async {
        guard let firstID = assetSetIDs.sorted().first,
              let apiClient, let credential = await apiClient.credential,
              let url = consoleSavesExportURL(forAssetSetID: firstID, baseURL: credential.baseURL)
        else { return }
#if UI_TESTING
        uiTestConsoleExportAttempts.append(url.absoluteString)
#else
        NSWorkspace.shared.open(url)
#endif
    }

    /// Recreates the save directory a `repairSaveDirectory` remedy points
    /// at, and reports whether it is writable afterwards.
    @discardableResult
    func repairSaveDirectory(for entry: CatalogueEntry) -> Bool {
        guard let saveDirectory = try? saveDirectoryURL(forAssetSetID: entry.id) else { return false }
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: saveDirectory.path
        )
        return FileManager.default.isWritableFile(atPath: saveDirectory.path)
    }

    func makeDownloadEngine() -> DownloadEngine {
        // The injected session is the same seam the coordinator uses, so
        // a test drives the row's download path through `StubURLProtocol`
        // and can assert whether a connection was actually opened — which
        // is what makes "an over-quota download is refused" provable
        // rather than merely reported.
        DownloadEngine(
            session: downloadSessionOverride ?? URLSession(configuration: .ephemeral),
            paths: appPaths,
            cas: casManager
        )
    }

    // MARK: - Quota enforcement on the real download path

    /// The outcome of the row's Download button. `.blocked` carries the
    /// verdict the reclaim prompt renders.
    enum DownloadAttempt: Equatable {
        case notPaired
        case blocked(QuotaVerdict)
        case completed
        case failed(String)
    }

    /// The whole of what `GameRowView`'s Download button does, living
    /// here rather than inside the view so the quota gate sits on a seam
    /// a test can drive exactly as the shipped row drives it. The gate
    /// runs *before* the first connection is opened: a blocked verdict
    /// returns without touching `DownloadEngine` at all.
    func attemptDownload(for entry: CatalogueEntry) async -> DownloadAttempt {
        let verdict = quotaVerdict(forDownloading: entry)
        guard verdict.allowed else { return .blocked(verdict) }

        guard let apiClient = await apiClientIfAvailable(),
              let credential = await apiClient.credential else { return .notPaired }

        let engine = makeDownloadEngine()
        do {
            for member in Self.requiredMembers(of: entry) where !casManager.contains(member.sha256) {
                // The digest is server-supplied and becomes a URL path
                // component, so it is validated before it is spliced
                // (CR-02) — the same rule the coordinator's `blobURL`
                // follows.
                let digest = try PathSafety.validatedDigest(member.sha256)
                let url = credential.baseURL
                    .appendingPathComponent("api/v1/blobs")
                    .appendingPathComponent(digest)
                try await engine.download(
                    sha256: digest,
                    from: url,
                    headers: ["Authorization": "Bearer \(credential.token)"],
                    expectedSize: member.size
                )
            }
            return .completed
        } catch {
            return .failed("Download failed: \(error)")
        }
    }

    /// The bytes a download of `entry` would actually add to the cache:
    /// required members that are not already committed. Members already
    /// in the CAS cost nothing, so counting them would block downloads
    /// that free-cost nothing.
    func pendingDownloadBytes(for entry: CatalogueEntry) -> Int {
        Self.requiredMembers(of: entry)
            .filter { !casManager.contains($0.sha256) }
            .reduce(0) { $0 + $1.size }
    }

    /// The capacity verdict for downloading `entry` right now. This is
    /// the gate `GameRowView.download()` consults before it opens a
    /// single connection — before this existed the row went straight to
    /// `DownloadEngine` and the cache could grow without bound.
    func quotaVerdict(forDownloading entry: CatalogueEntry) -> QuotaVerdict {
        quotaManager.verdict(forAdditional: pendingDownloadBytes(for: entry))
    }

    /// Raising the quota can only help when the *quota* was the limit
    /// hit. The free-space floor outranks it (D-21), so a floor-blocked
    /// download offers reclaim only — never a "raise the quota" button
    /// that would change nothing.
    func canRaiseQuota(for verdict: QuotaVerdict) -> Bool {
        verdict.limitHit == .quota
    }

    /// Raises the quota by exactly the reported shortfall. Returns false
    /// (and changes nothing) when the floor was the limit hit.
    @discardableResult
    func raiseQuota(toCover verdict: QuotaVerdict) -> Bool {
        guard canRaiseQuota(for: verdict) else { return false }
        try? quotaManager.setQuota(bytes: quotaManager.policy().quotaBytes + verdict.shortfallBytes)
        return true
    }

    func setQuota(bytes: Int) {
        try? quotaManager.setQuota(bytes: max(0, bytes))
    }

    // MARK: - Storage surfaces

    /// Everything `StorageView` and `QuotaSettingsView` render, read from
    /// the real stores at call time — never remembered state (D-21).
    struct StorageSnapshot {
        let policy: QuotaPolicy
        let usedBytes: Int
        let candidates: [EvictionCandidate]
        let pinnedGames: [PinnedGameRow]
        let unreferenced: [UnreferencedObject]
        let quarantined: [QuarantinedPartial]
        /// D-40's interruptive-tier input (MC-01), keyed by candidate id
        /// — real counts read from `SaveStore`, never the empty `[:]`
        /// `StorageView` used to be handed. A candidate absent here (or
        /// present with `0`) raises no interruptive modal when reclaimed.
        let onlyOnThisMacCounts: [String: Int]
    }

    func storageSnapshot() -> StorageSnapshot {
        let titles = catalogueTitles()
        let pinned = pinStore.allPinned().sorted().map {
            PinnedGameRow(id: $0, title: titles[$0] ?? $0)
        }
        let candidates = evictionPlanner.candidates()
        let counts = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate -> (String, Int)? in
            let count = onlyOnThisMacCount(forAssetSetID: candidate.id)
            return count > 0 ? (candidate.id, count) : nil
        })
        return StorageSnapshot(
            policy: quotaManager.policy(),
            usedBytes: quotaManager.usedBytes(),
            candidates: candidates,
            pinnedGames: pinned,
            unreferenced: evictionPlanner.unreferencedObjects(),
            quarantined: evictionPlanner.quarantinedPartials(),
            onlyOnThisMacCounts: counts
        )
    }

    /// The reclaim candidates in `ReclaimPromptView`'s own row shape —
    /// the prompt deliberately does not depend on `EvictionCandidate`.
    /// MC-01: `onlyOnThisMacCount` is now the real count read from
    /// `SaveStore`, never the zero default.
    func reclaimCandidateRows() -> [ReclaimCandidateRow] {
        evictionPlanner.candidates().map {
            ReclaimCandidateRow(
                id: $0.id, title: $0.title, bytes: $0.bytes,
                onlyOnThisMacCount: onlyOnThisMacCount(forAssetSetID: $0.id)
            )
        }
    }

    /// Reclaims exactly the named games through an explicit
    /// `EvictionPlan` — nothing is ever deleted outside a plan (D-21).
    /// Returns the bytes freed; an empty selection is a calm no-op.
    @discardableResult
    func reclaim(gameIDs: Set<String>) -> Int {
        let plan = evictionPlanner.plan(for: gameIDs)
        guard !plan.objectSHAs.isEmpty else { return 0 }
        try? evictionPlanner.execute(plan)
        return plan.totalBytes
    }

    func removeQuarantinedPartial(atPath path: String) {
        try? evictionPlanner.removeQuarantined(atPath: path)
    }

    // MARK: - Pins

    func isPinned(assetSetID: String) -> Bool {
        pinStore.isPinned(assetSetID)
    }

    /// The pin toggle behind every library row's Pin button. Returns the
    /// resulting pinned state. Unpinning deletes nothing — it only makes
    /// the game eligible for a later, explicitly confirmed reclaim.
    @discardableResult
    func togglePin(assetSetID: String) -> Bool {
        let wasPinned = pinStore.isPinned(assetSetID)
        if wasPinned {
            try? pinStore.unpin(assetSetID: assetSetID)
        } else {
            try? pinStore.pin(assetSetID: assetSetID)
        }
        return !wasPinned
    }

    // MARK: - Download queue surface

    private func catalogueTitles() -> [String: String] {
        Dictionary(catalogueStore.fetchAll().map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { first, _ in first })
    }

    /// The persistent queue in `DownloadsView`'s row shape, with the live
    /// percentage for whatever is actually transferring.
    func downloadRows() -> [DownloadRow] {
        let titles = catalogueTitles()
        return downloadQueue.list().map { item in
            DownloadRow(
                id: item.id,
                assetSetID: item.assetSetID,
                title: titles[item.assetSetID] ?? item.assetSetID,
                sha256: item.sha256,
                sizeBytes: item.size,
                state: item.state,
                progressPercent: item.state == .active ? downloadProgressByAssetSet[item.assetSetID] : nil
            )
        }
    }

    func pauseDownload(id: String) { try? downloadQueue.pause(id: id) }
    func resumeDownload(id: String) { try? downloadQueue.resume(id: id); Task { await startDownloadQueue() } }
    func cancelDownload(id: String) { try? downloadQueue.cancel(id: id) }

    /// Reorder by one position, expressed in `DownloadQueue`'s own
    /// between-two-neighbours vocabulary so no other row is renumbered.
    func moveDownloadUp(id: String) {
        let items = downloadQueue.list()
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return }
        try? downloadQueue.reorder(
            id: id,
            afterID: index >= 2 ? items[index - 2].id : nil,
            beforeID: items[index - 1].id
        )
    }

    func moveDownloadDown(id: String) {
        let items = downloadQueue.list()
        guard let index = items.firstIndex(where: { $0.id == id }), index < items.count - 1 else { return }
        try? downloadQueue.reorder(
            id: id,
            afterID: items[index + 1].id,
            beforeID: index + 2 < items.count ? items[index + 2].id : nil
        )
    }

    /// Enqueues every required member of `entry` onto the persistent
    /// queue and starts the scheduler.
    func enqueueDownload(for entry: CatalogueEntry) {
        try? downloadQueue.enqueueGame(entry)
        Task { await startDownloadQueue() }
    }

    // MARK: - Download coordinator

    /// Builds the one `DownloadCoordinator` this app uses, wiring its two
    /// injected seams to the real `PinStore` and `QuotaManager` exactly
    /// as its own doc comments specify. Returns `nil` until a pairing
    /// credential exists — there is no blob base URL to download from
    /// before that.
    @discardableResult
    func downloadCoordinatorIfAvailable() async -> DownloadCoordinator? {
        if let downloadCoordinator { return downloadCoordinator }
        guard let client = await apiClientIfAvailable(),
              let credential = await client.credential else { return nil }

        let session: URLSession
        if let downloadSessionOverride {
            session = downloadSessionOverride
        } else {
            // `DownloadCoordinator` calls `DownloadEngine.download` with
            // no per-request headers, so the bearer token is carried by
            // the session configuration instead — the one adaptation
            // this wiring needed to reach the coordinator's API as it
            // already exists.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(credential.token)"]
            session = URLSession(configuration: configuration)
        }

        let base = credential.baseURL
        let coordinator = DownloadCoordinator(
            queue: downloadQueue,
            engine: DownloadEngine(session: session, paths: appPaths, cas: casManager),
            cas: casManager,
            localStore: localStore,
            reachability: reachability,
            blobURL: { sha256 in
                // The digest is server-supplied and becomes a URL path
                // component, so it is validated before it is spliced
                // (CR-02). An invalid digest yields the bare base URL,
                // which `DownloadEngine.download` never reaches: it
                // rejects the same digest at its own front door first.
                guard (try? PathSafety.validatedDigest(sha256)) != nil else { return base }
                return base.appendingPathComponent("api/v1/blobs").appendingPathComponent(sha256)
            }
        )

        await coordinator.setIsPinned { [pinStore] assetSetID in pinStore.isPinned(assetSetID) }
        await coordinator.setQuotaCheck { [quotaManager] bytes in
            let verdict = quotaManager.verdict(forAdditional: bytes)
            guard !verdict.allowed else { return (true, nil) }
            return (false, Self.quotaReason(verdict))
        }

        let events = coordinator.events
        Task { @MainActor [weak self] in
            for await event in events { self?.apply(event) }
        }

        downloadCoordinator = coordinator
        return coordinator
    }

    /// Starts (or resumes) the queue scheduler. Safe to call repeatedly.
    func startDownloadQueue() async {
        await downloadCoordinatorIfAvailable()?.start()
    }

    private func apply(_ event: CoordinatorEvent) {
        switch event {
        case .started(_, let assetSetID, _):
            downloadProgressByAssetSet[assetSetID] = 0
        case .progress(_, let assetSetID, _, let percent):
            downloadProgressByAssetSet[assetSetID] = percent
        case .committed(_, let assetSetID, _):
            downloadProgressByAssetSet.removeValue(forKey: assetSetID)
            libraryViewModel.refresh()
        case .blocked(let itemID, let assetSetID, let reason):
            downloadProgressByAssetSet.removeValue(forKey: assetSetID)
            lastBlockedDownload = (itemID: itemID, assetSetID: assetSetID, reason: reason)
        case .digestMismatchRequeued, .wentOffline, .resumedOnline:
            break
        }
    }

    /// The plainly-worded reason a blocked verdict carries into the
    /// coordinator's `.blocked` event and on to the user.
    static func quotaReason(_ verdict: QuotaVerdict) -> String {
        let limitName = verdict.limitHit == .floor ? "free-space floor" : "quota"
        return "Needs \(ByteFormatting.formatBytes(verdict.shortfallBytes)) more than your \(limitName) allows."
    }
}
