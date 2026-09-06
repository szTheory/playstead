import SwiftUI

/// A row's readiness, derived at read time from the CAS rather than
/// stored — the same discipline CACH-02's six states use, narrowed to
/// what this tracer needs: not yet cached, actively downloading, or
/// ready to play. Per D-17, a row exposes the action that is actually
/// available (Download or Play) — never a disabled Play.
enum GameRowStatus: Equatable {
    case needsDownload
    case downloading
    case ready
    /// At least one readiness check other than "the files aren't here
    /// yet" is blocking. Carries the whole report so the row can show
    /// the blocking condition and its remedy rather than a raw error
    /// string.
    case blocked(ReadinessReport)
    case error(String)
}

/// One selection-scoped command emitted by the library composition root.
/// The sequence makes repeated requests for the same asset observable while
/// the asset id ensures exactly one row handles each command.
struct LibraryDownloadCommand: Equatable {
    let sequence: Int
    let assetSetID: String
}

/// A functional (not yet visually designed) row for one catalogue entry:
/// title, system, and exactly one status-appropriate action. The visual
/// identity, shelves, sidebar, and status vocabulary are plan 03-06's
/// work against the UI spec (D-12 through D-17) — this row exists so
/// the tracer can prove the read-download-play path end to end.
struct GameRowView: View {
    let entry: CatalogueEntry
    var downloadCommand: LibraryDownloadCommand?

    @Environment(AppEnvironment.self) private var environment
    @State private var status: GameRowStatus = .needsDownload
    @State private var lastExit: AdapterExit?
    @State private var showsReadinessSheet = false
    /// The blocked capacity verdict that stopped the last download
    /// attempt, and the prompt it opens. `nil` whenever nothing is
    /// blocked — the row never remembers a stale refusal.
    @State private var quotaBlock: QuotaVerdict?
    @State private var showsReclaimPrompt = false
    /// The most recent launch's `SaveLaunchNotice`, when the save plan
    /// carried one (WINDOWS #37). Surfaced inline in the detail view's
    /// Save section once that surface exists — never as a modal, a
    /// toast, or an entry in the card's status slot (D-45, 04-CONTEXT.md
    /// "Launch-path notices"). No detail view exists yet in this
    /// codebase to render it into; this property is the seam a future
    /// plan wires up, held here rather than discarded so the notice is
    /// never silently lost.
    @State private var saveLaunchNotice: SaveLaunchNotice?
    /// Owned by the stable row rather than a modifier hosted inside `List`.
    /// This keeps SwiftUI focus and the final actionable AX button on the
    /// same identity when a row is recycled or its status is refreshed.
    @FocusState private var downloadActionHasFocus: Bool
    /// Bumped after a pin toggle so the row re-reads `PinStore` (pins
    /// live in SQLite, not in an observable view model).
    @State private var pinRevision = 0

    private var requiredMembers: [(sha256: String, size: Int)] {
        AppEnvironment.requiredMembers(of: entry).map { (sha256: $0.sha256, size: $0.size) }
    }

    /// Whether this game is pinned. `pinRevision` is read here so a
    /// toggle invalidates the row — pins live in SQLite, not in an
    /// observable view model.
    private var isPinned: Bool {
        _ = pinRevision
        return environment.isPinned(assetSetID: entry.id)
    }

    /// The report currently being shown, if any — `.blocked` carries it,
    /// and a sheet opened from a ready row re-evaluates on demand.
    private var blockingReport: ReadinessReport? {
        if case .blocked(let report) = status { return report }
        return nil
    }

    static func downloadActionIdentifier(assetSetID: String) -> String {
        "playstead.game.\(assetSetID).download"
    }

    static func summaryIdentifier(assetSetID: String) -> String {
        "playstead.game.\(assetSetID).summary"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.headline)
                Text(entry.system)
                    .font(.caption)
                    .foregroundStyle(.primary)
                if case .error(let message) = status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let blockingReport, let first = blockingReport.checks.first(where: { $0.outcome.isBlocking }) {
                    Text(Self.blockingSummary(first))
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
                if let lastExit {
                    Text("Last exit: \(String(describing: lastExit))")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(rowSummaryAccessibilityLabel)
            .accessibilityIdentifier(Self.summaryIdentifier(assetSetID: entry.id))
            Spacer()
            curationButtons
            actionButton
        }
        .padding(.vertical, 4)
        .task {
            refreshStatus()
        }
        .onChange(of: downloadCommand) { _, command in
            guard command?.assetSetID == entry.id else { return }
            Task { await download() }
        }
        .sheet(isPresented: $showsReadinessSheet) {
            ReadinessSheetView(
                entry: entry,
                report: blockingReport ?? environment.readinessReport(for: entry),
                onRefresh: { refreshStatus() },
                onDownload: {
                    showsReadinessSheet = false
                    Task { await download() }
                },
                onPlay: {
                    showsReadinessSheet = false
                    Task { await play() }
                },
                onClose: {
                    showsReadinessSheet = false
                    refreshStatus()
                },
                saveHistorySessions: { environment.saveHistorySessions(forAssetSetID: entry.id) },
                saveRollupSummary: { environment.saveRollupSummary(forAssetSetID: entry.id) }
            )
            .environment(environment)
        }
        .sheet(isPresented: $showsReclaimPrompt) {
            reclaimPrompt
        }
    }

    private var rowSummaryAccessibilityLabel: String {
        var parts = [entry.displayTitle, SystemRegistry.entry(for: entry.system).displayName]
        if let blockingReport,
           let first = blockingReport.checks.first(where: { $0.outcome.isBlocking }) {
            parts.append(Self.blockingSummary(first))
        }
        return parts.joined(separator: ", ")
    }

    /// The blocked-capacity surface. Every button here does real work
    /// against the app's shared `QuotaManager`/`EvictionPlanner`: raising
    /// the quota persists it, reclaiming executes an explicit
    /// `EvictionPlan`, and both then retry the download that was refused.
    @ViewBuilder
    private var reclaimPrompt: some View {
        if let verdict = quotaBlock, let limitHit = verdict.limitHit {
            ReclaimPromptView(
                limitHit: limitHit,
                shortfallBytes: verdict.shortfallBytes,
                canRaiseQuota: environment.canRaiseQuota(for: verdict),
                candidates: environment.reclaimCandidateRows(),
                onRaiseQuota: {
                    environment.raiseQuota(toCover: verdict)
                    dismissReclaimPromptAndRetry()
                },
                onReclaim: { selected in
                    environment.reclaim(gameIDs: selected)
                    dismissReclaimPromptAndRetry()
                },
                onCancel: {
                    showsReclaimPrompt = false
                    quotaBlock = nil
                },
                onExportOnlyCopy: { ids in
                    Task { await environment.openConsoleSavesExport(forAssetSetIDs: ids) }
                }
            )
            .frame(minWidth: 460, minHeight: 320)
        }
    }

    private func dismissReclaimPromptAndRetry() {
        showsReclaimPrompt = false
        quotaBlock = nil
        Task { await download() }
    }

    /// The one-line summary a blocked row shows inline, so the reason is
    /// visible without opening anything.
    static func blockingSummary(_ check: ReadinessCheck) -> String {
        guard case .blocked(let text) = check.outcome else { return check.finding }
        return text
    }

    /// Favorite and Queue, the two curation mutations reachable from any
    /// library row. Both go through `AppEnvironment`'s shared view models,
    /// so the intent lands in the one shared `Outbox` and the drain
    /// trigger fires — the row is where the curation slice actually
    /// becomes reachable from the shipped app.
    @ViewBuilder
    private var curationButtons: some View {
        let isFavorited = environment.favoritesViewModel.isFavorited(assetSetID: entry.id)
        let isQueued = environment.queueViewModel.isQueued(assetSetID: entry.id)

        Button(isFavorited ? "Unfavorite" : "Favorite") {
            environment.toggleFavorite(assetSetID: entry.id)
        }
        .accessibilityLabel(Self.favoriteActionLabel(title: entry.displayTitle, isFavorited: isFavorited))

        Button(isQueued ? "Remove from Queue" : "Add to Queue") {
            environment.toggleQueued(assetSetID: entry.id)
        }
        .accessibilityLabel(Self.queueActionLabel(title: entry.displayTitle, isQueued: isQueued))

        // Pinning is the only way a game becomes protected from reclaim
        // and prioritised by the download scheduler — `PinStore` had no
        // reachable caller at all before this button existed.
        Button(isPinned ? "Unpin" : "Pin") {
            environment.togglePin(assetSetID: entry.id)
            pinRevision += 1
        }
        .accessibilityLabel(Self.pinActionLabel(title: entry.displayTitle, isPinned: isPinned))
    }

    /// Accessible names are the action verb plus its subject
    /// (03-UI-SPEC.md's QUAL-01 floor), pure so they can be asserted
    /// without hosting a live view.
    static func favoriteActionLabel(title: String, isFavorited: Bool) -> String {
        isFavorited ? "Remove \(title) from Favorites" : "Add \(title) to Favorites"
    }

    static func queueActionLabel(title: String, isQueued: Bool) -> String {
        isQueued ? "Remove \(title) from Queue" : "Add \(title) to Queue"
    }

    static func pinActionLabel(title: String, isPinned: Bool) -> String {
        isPinned ? "Unpin \(title), allowing it to be reclaimed" : "Pin \(title) to keep it on this Mac"
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .needsDownload:
            Button("Download") { Task { await download() } }
                .focused($downloadActionHasFocus)
                .accessibilityIdentifier(Self.downloadActionIdentifier(assetSetID: entry.id))
                .overlay {
                    RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                        .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                        .opacity(PlaysteadFocusRing.opacity(isFocused: downloadActionHasFocus))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
        case .downloading:
            ProgressView().controlSize(.small)
        case .ready:
            Button("Play") { Task { await play() } }
        case .blocked:
            // D-17: the row offers the action that is actually available.
            // With something other than the files blocking, that action
            // is seeing the blocker and its remedy — never a disabled
            // Play, and never a Play that fails with a raw error.
            Button("What's needed") { showsReadinessSheet = true }
        case .error:
            Button("Retry") { Task { await download() } }
        }
    }

    /// Derives the row's action from the real six-check readiness report,
    /// not from a bare cache lookup. Missing files stay a Download — the
    /// row's own remedy for that blocker — and every other blocking
    /// condition routes to the report and its remedy.
    private func refreshStatus() {
        guard !requiredMembers.isEmpty else { return }
        status = Self.status(for: environment.readinessReport(for: entry))
    }

    /// The row's action, derived from a readiness report — pure, so the
    /// exact mapping the shipped row uses can be asserted without
    /// hosting a live view.
    static func status(for report: ReadinessReport) -> GameRowStatus {
        if report.isReady { return .ready }
        if report.checks.contains(where: { $0.kind == .gameAssets && $0.outcome.isBlocking }) {
            return .needsDownload
        }
        return .blocked(report)
    }

    /// The row's Download button. The whole attempt — including the
    /// capacity gate that runs before any connection is opened — lives on
    /// `AppEnvironment` so the shipped path and the tested path are the
    /// same code. Before that gate existed the row went straight to
    /// `DownloadEngine`, so nothing in the shipped app ever consulted
    /// `QuotaManager` and the cache could grow past both the quota and
    /// the free-space floor.
    @MainActor
    private func download() async {
        status = .downloading
        switch await environment.attemptDownload(for: entry) {
        case .notPaired:
            status = .error("Not paired")
        case .blocked(let verdict):
            quotaBlock = verdict
            showsReclaimPrompt = true
            refreshStatus()
        case .completed:
            refreshStatus()
        case .failed(let message):
            status = .error(message)
        }
    }

    @MainActor
    private func play() async {
        guard let adapterHost = environment.adapterHost else {
            status = .error("Adapter unavailable")
            return
        }

        let members = entry.members.compactMap { member -> (sha256: String, declaredName: String)? in
            guard let sha256 = member.sha256, let name = member.name else { return nil }
            return (sha256, name)
        }

        // The real gate: six local checks, every blocking one carrying a
        // remedy. Before this, Play ran no readiness check at all and
        // surfaced failures as an untyped "Launch failed: …" string.
        let report = environment.readinessReport(for: entry)
        guard report.isReady else {
            status = .blocked(report)
            showsReadinessSheet = true
            return
        }

        // Declared outside the `do` so the `catch` can close a capture
        // session `begin()` already opened.
        var saveCapture: SaveCaptureWiring?

        do {
            let materialized = try environment.launchMaterializer.materialize(assetSetID: entry.id, members: members)
            guard let romURL = materialized.files.first else {
                status = .error("No launchable member")
                return
            }
            // The same validated save directory the readiness check just
            // confirmed is writable — the asset set id is server-supplied
            // and is validated as a safe bare filename before it becomes
            // a path component (CR-01/CR-02).
            let saveDir = try environment.saveDirectoryURL(forAssetSetID: entry.id)
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

            // A validated, managed BIOS for this ROM's system (if any)
            // must actually reach the emulator's launch arguments —
            // otherwise the readiness/capability UI's "BIOS validated
            // and in use" claim would be false (P2-CR-002).
            let biosPath = environment.biosStore.managedRecord(forSystem: entry.system)
                .map { environment.biosStore.managedPath(forSHA256: $0.sha256).path }

            // Recent and Continue exist only because sessions are
            // recorded; `PlaySessionRecorder` never sits between the user
            // and the launch (every write inside it swallows its own
            // failure), so this cannot make a launch fail.
            let sessionID = environment.playSessionRecorder.began(assetSetID: entry.id)
            environment.refreshCurationViewModels()

            // D-44/WINDOWS #37: build the save plan for this launch and
            // pass it to `executeSavePlan`, the seam `AdapterHost`
            // invokes inside its own per-assetSetID mutex span, right
            // before spawning the emulator. The default `nil` this
            // parameter takes everywhere else is never taken here, on
            // the real Play path -- this is the exact wiring that was
            // missing (04-07 built the seam, nothing called it).
            let saveLaunch = GameRowView.buildSaveLaunchPlan(
                environment: environment, entry: entry, members: members, romURL: romURL, saveDir: saveDir
            )
            saveLaunchNotice = saveLaunch.notice

            // WINDOWS #45/#44: the symmetric half of the same gap. The
            // restore side above was wired in 04-14; nothing in the
            // shipped app had ever captured a save during play, because
            // `SaveCapturePoller` had no production construction site.
            // `begin()` runs before `adapterHost.launch` so D-04's
            // session-start baseline check reads the artifact as the
            // user left it -- before the save plan restores over it.
            saveCapture = GameRowView.buildSaveCaptureCoordinator(
                environment: environment, entry: entry, members: members, targetURL: saveLaunch.targetURL
            )
            await saveCapture?.begin()

            // `onExit` is `@Sendable`, and a mutable local cannot cross
            // into it -- the wiring is snapshotted into a `let` first.
            let capturedSession = saveCapture
            try await adapterHost.launch(
                assetSetID: entry.id, romPath: romURL.path, saveDir: saveDir.path, biosPath: biosPath,
                executeSavePlan: saveLaunch.executeSavePlan
            ) { exit in
                Task { @MainActor in
                    // D-05's settle-then-promote pass, before the
                    // session is recorded as ended. `end()` never
                    // throws, so a capture problem can never turn a
                    // finished play session into a visible failure.
                    await capturedSession?.end()
                    lastExit = exit
                    environment.playSessionRecorder.ended(sessionID)
                    environment.refreshCurationViewModels()
                }
            }
        } catch {
            // The emulator never spawned (or never started), so no
            // `onExit` will ever fire -- close the capture session here
            // or its poll loop would run for the rest of the app's life.
            await saveCapture?.end()
            status = .error("Launch failed: \(error)")
        }
    }

    /// One launch's resolved save plan: the target `.sav` path, the
    /// notice (if any) the plan carries, and the closure `AdapterHost`
    /// invokes to execute it. Extracted from `play()` (which is a
    /// private `@MainActor` method SwiftUI drives, not directly
    /// callable from a test) so `PlayPathSaveWiringTests` can assert
    /// this exact wiring -- that a write-requiring plan reaches the
    /// executor with the expected target path, and that a throwing plan
    /// prevents `AdapterHost.launch` from ever spawning the emulator --
    /// without needing to drive `play()`'s SwiftUI machinery end to end.
    /// This is the regression WINDOWS #37 recorded: the seam existed and
    /// no call site ever used it.
    static func buildSaveLaunchPlan(
        environment: AppEnvironment,
        entry: CatalogueEntry,
        members: [(sha256: String, declaredName: String)],
        romURL: URL,
        saveDir: URL
    ) -> (plan: SavePlan, targetURL: URL, notice: SaveLaunchNotice?, executeSavePlan: () throws -> Void) {
        // The save contract names this `{saveDir}/{romBaseName}.sav`
        // (SavePlanExecutor's own doc comment) -- `romBaseName` is the
        // materialized ROM's own filename, extension stripped, since no
        // production caller has defined this convention before now.
        // Stated once in `SaveCapturePaths` so the restore half here,
        // the capture half (`buildSaveCaptureCoordinator`) and the
        // crash-recovery half (`recoverAbandonedSaveSessionsAtLaunch`)
        // can never derive different paths for the same artifact.
        let targetURL = SaveCapturePaths.targetURL(
            saveDirectory: saveDir, romFileName: romURL.lastPathComponent
        )
        // `content_key` is the ROM's own sha256 (D-10), never
        // `assetSetID` -- the first required member is the ROM for
        // every system this client supports today. Falling back to
        // `entry.id` only guards a members list this codebase's own
        // readiness gate should never allow to reach here empty.
        let contentKey = members.first?.sha256 ?? entry.id

        let contextBuilder = LaunchSaveContextBuilder(
            saveStore: SaveStore(localStore: environment.localStore),
            casManager: environment.casManager,
            saveContract: environment.adapterCatalog?.descriptor.saveContract,
            systemID: entry.system
        )
        let context = contextBuilder.buildContext(contentKey: contentKey, targetURL: targetURL)
        let plan = LaunchSavePlanner.plan(context: context)
        let executor = SavePlanExecutor(environment: LaunchSaveEnvironment(casManager: environment.casManager))
        let saveStore = contextBuilder.saveStore

        let executeSavePlan: () throws -> Void = {
            try executor.execute(plan, targetURL: targetURL)
            // Plan 04-22 task 1: only AFTER a successful execute --
            // `.restore` and `.fastForward` are the two plans that place
            // another revision's bytes at the live artifact path; `.fresh`
            // and `.keep` mark nothing. Marking errors are swallowed
            // (`try?`) so provenance bookkeeping can never turn a
            // successful restore into a failed launch.
            let restoredDigest: String?
            switch plan {
            case let .restore(digest, _): restoredDigest = digest
            case let .fastForward(digest): restoredDigest = digest
            case .fresh, .keep: restoredDigest = nil
            }
            guard let restoredDigest,
                  let line = saveStore.fetchLine(contentKey: contentKey, saveKind: "battery", slot: "0"),
                  let revision = saveStore.fetchRevisions(saveLineID: line.id).first(where: { $0.blobSHA256 == restoredDigest })
            else { return }
            try? saveStore.markRestoredHere(revisionID: revision.id, at: ISO8601DateFormatter().string(from: Date()))
        }

        return (plan, targetURL, Self.notice(for: plan), executeSavePlan)
    }

    /// One launch's capture wiring: a fresh `SaveSessionCoordinator`
    /// bound to this launch's save line, the exact artifact path the
    /// save plan resolved, and the capture directory its durable blobs
    /// land in.
    ///
    /// Extracted from `play()` for the same reason `buildSaveLaunchPlan`
    /// was (04-14): `play()` is a private `@MainActor` SwiftUI method a
    /// test cannot drive, so wiring written inline there is wiring
    /// nothing can assert -- which is exactly how WINDOWS #45 happened.
    /// `PlayPathSaveWiringTests` asserts against this function and
    /// against `play()`'s source for the call itself.
    ///
    /// Returns `nil` only when the save line or the capture directory
    /// cannot be resolved at all; a launch then proceeds with no capture
    /// rather than being refused, because a bookkeeping problem must
    /// never stop the user playing.
    static func buildSaveCaptureCoordinator(
        environment: AppEnvironment,
        entry: CatalogueEntry,
        members: [(sha256: String, declaredName: String)],
        targetURL: URL
    ) -> SaveCaptureWiring? {
        // Same `content_key` resolution as `buildSaveLaunchPlan` (D-10):
        // the ROM's own sha256, never `assetSetID`. The capture half and
        // the restore half must key the same line or a captured save
        // would never be found again at launch.
        let contentKey = members.first?.sha256 ?? entry.id
        guard
            // The launch path may be this line's first-ever sighting, so
            // the line is resolved (created if absent) rather than only
            // fetched -- a first play session with nowhere to record its
            // promotion would capture bytes and drop the row.
            let line = try? environment.saveStore.resolveLine(
                contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: UUIDv7.generate()
            ),
            let captureDirectory = try? environment.saveCaptureDirectoryURL(forAssetSetID: entry.id)
        else { return nil }

        return SaveCaptureWiring(
            coordinator: environment.makeSaveSessionCoordinator(),
            saveLineID: line.id,
            targetURL: targetURL,
            destinationDirectory: captureDirectory,
            artifactRelativePath: targetURL.lastPathComponent
        )
    }

    private static func notice(for plan: SavePlan) -> SaveLaunchNotice? {
        switch plan {
        case .fresh(let notice): return notice
        case .restore(_, let notice): return notice
        case .fastForward: return nil
        case .keep(let notice): return notice
        }
    }
}
