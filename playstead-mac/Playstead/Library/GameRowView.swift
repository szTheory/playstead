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

/// A functional (not yet visually designed) row for one catalogue entry:
/// title, system, and exactly one status-appropriate action. The visual
/// identity, shelves, sidebar, and status vocabulary are plan 03-06's
/// work against the UI spec (D-12 through D-17) — this row exists so
/// the tracer can prove the read-download-play path end to end.
struct GameRowView: View {
    let entry: CatalogueEntry

    @Environment(AppEnvironment.self) private var environment
    @State private var status: GameRowStatus = .needsDownload
    @State private var lastExit: AdapterExit?
    @State private var showsReadinessSheet = false

    private var requiredMembers: [(sha256: String, size: Int)] {
        AppEnvironment.requiredMembers(of: entry).map { (sha256: $0.sha256, size: $0.size) }
    }

    /// The report currently being shown, if any — `.blocked` carries it,
    /// and a sheet opened from a ready row re-evaluates on demand.
    private var blockingReport: ReadinessReport? {
        if case .blocked(let report) = status { return report }
        return nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.headline)
                Text(entry.system)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .error(let message) = status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let blockingReport, let first = blockingReport.checks.first(where: { $0.outcome.isBlocking }) {
                    Text(Self.blockingSummary(first))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let lastExit {
                    Text("Last exit: \(String(describing: lastExit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            curationButtons
            actionButton
        }
        .padding(.vertical, 4)
        .task {
            refreshStatus()
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
                }
            )
            .environment(environment)
        }
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

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .needsDownload:
            Button("Download") { Task { await download() } }
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

    @MainActor
    private func download() async {
        guard let apiClient = await environment.apiClientIfAvailable() else {
            status = .error("Not paired")
            return
        }
        guard let credential = await apiClient.credential else {
            status = .error("Not paired")
            return
        }

        status = .downloading
        let engine = environment.makeDownloadEngine()

        do {
            for member in requiredMembers {
                let url = credential.baseURL.appendingPathComponent("/api/v1/blobs/\(member.sha256)")
                try await engine.download(
                    sha256: member.sha256,
                    from: url,
                    headers: ["Authorization": "Bearer \(credential.token)"]
                )
            }
            refreshStatus()
        } catch {
            status = .error("Download failed: \(error)")
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

            try await adapterHost.launch(romPath: romURL.path, saveDir: saveDir.path, biosPath: biosPath) { exit in
                Task { @MainActor in
                    lastExit = exit
                    environment.playSessionRecorder.ended(sessionID)
                    environment.refreshCurationViewModels()
                }
            }
        } catch {
            status = .error("Launch failed: \(error)")
        }
    }
}
