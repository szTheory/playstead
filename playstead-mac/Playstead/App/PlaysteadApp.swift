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
#if DEBUG
            if ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] == "1" {
                HostedRunnerFocusCanaryView()
            } else {
                libraryShell
            }
#else
            libraryShell
#endif
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

    private var libraryShell: some View {
        LibraryShellView()
            .environment(appEnvironment)
            .frame(minWidth: 960, minHeight: 560)
    }
}

#if DEBUG
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
        reachability: Reachability = Reachability(),
        downloadSession: URLSession? = nil
    ) {
        self.appPaths = paths
        self.downloadSessionOverride = downloadSession
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

        self.downloadQueue = DownloadQueue(localStore: store)

        let pinStore = PinStore(localStore: store)
        self.pinStore = pinStore
        // The cache root is the volume whose free space the floor is
        // measured against — the objects directory, not the app bundle.
        self.quotaManager = QuotaManager(localStore: store, cacheRootURL: paths.objects)
        self.evictionPlanner = EvictionPlanner(
            localStore: store, catalogueStore: catalogueStore, pinStore: pinStore, cas: cas, paths: paths
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
                    outcome: .blocked("Save directory not writable."),
                    finding: "This title's identifier can't be used as a folder name, so Playstead has nowhere safe to keep its saves.",
                    remedy: Remedy(title: "Repair save directory", action: .repairSaveDirectory)
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

        let engine = ReadinessEngine(
            cas: casManager,
            downloadQueue: downloadQueue,
            adapterInstallState: { installState },
            biosRequired: biosRequired,
            hasManagedBIOS: { hasBIOS },
            hasController: { hasController },
            saveDirectoryURL: saveDirectory
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
        guard let apiClient = await apiClientIfAvailable(),
              let credential = await apiClient.credential else { return .notPaired }

        let verdict = quotaVerdict(forDownloading: entry)
        guard verdict.allowed else { return .blocked(verdict) }

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
    }

    func storageSnapshot() -> StorageSnapshot {
        let titles = catalogueTitles()
        let pinned = pinStore.allPinned().sorted().map {
            PinnedGameRow(id: $0, title: titles[$0] ?? $0)
        }
        return StorageSnapshot(
            policy: quotaManager.policy(),
            usedBytes: quotaManager.usedBytes(),
            candidates: evictionPlanner.candidates(),
            pinnedGames: pinned,
            unreferenced: evictionPlanner.unreferencedObjects(),
            quarantined: evictionPlanner.quarantinedPartials()
        )
    }

    /// The reclaim candidates in `ReclaimPromptView`'s own row shape —
    /// the prompt deliberately does not depend on `EvictionCandidate`.
    func reclaimCandidateRows() -> [ReclaimCandidateRow] {
        evictionPlanner.candidates().map {
            ReclaimCandidateRow(id: $0.id, title: $0.title, bytes: $0.bytes)
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
