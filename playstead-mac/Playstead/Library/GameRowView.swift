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

    private var requiredMembers: [(sha256: String, size: Int)] {
        entry.members
            .filter { $0.required }
            .compactMap { member in
                guard let sha256 = member.sha256, let size = member.size else { return nil }
                return (sha256, size)
            }
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
                if let lastExit {
                    Text("Last exit: \(String(describing: lastExit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, 4)
        .task {
            refreshStatus()
        }
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
        case .error:
            Button("Retry") { Task { await download() } }
        }
    }

    private func refreshStatus() {
        guard !requiredMembers.isEmpty else { return }
        let result = environment.preflightChecker.check(requiredMembers: requiredMembers)
        status = (result == .ready) ? .ready : .needsDownload
    }

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

    private func play() async {
        guard let adapterHost = environment.adapterHost else {
            status = .error("Adapter unavailable")
            return
        }

        let members = entry.members.compactMap { member -> (sha256: String, declaredName: String)? in
            guard let sha256 = member.sha256, let name = member.name else { return nil }
            return (sha256, name)
        }

        do {
            let materialized = try environment.launchMaterializer.materialize(assetSetID: entry.id, members: members)
            guard let romURL = materialized.files.first else {
                status = .error("No launchable member")
                return
            }
            let saveDir = environment.appPaths.root
                .appendingPathComponent("saves", isDirectory: true)
                .appendingPathComponent(entry.id, isDirectory: true)
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

            try await adapterHost.launch(romPath: romURL.path, saveDir: saveDir.path) { exit in
                Task { @MainActor in
                    lastExit = exit
                }
            }
        } catch {
            status = .error("Launch failed: \(error)")
        }
    }
}
