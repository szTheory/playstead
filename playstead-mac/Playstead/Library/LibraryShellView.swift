import SwiftUI

/// A functional library shell: renders the persisted catalogue mirror as
/// a plain list, refreshing it from `/api/v1/snapshot` in the
/// background. No downloading happens here — task 2/3 of this plan add
/// the cache/adapter layers this view grows a Download/Play action for.
struct LibraryShellView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [CatalogueEntry] = []
    @State private var refreshError: String?

    var body: some View {
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
        .navigationTitle("Library")
        .task {
            loadFromLocalStore()
            await refreshFromServer()
        }
    }

    private func loadFromLocalStore() {
        entries = environment.localStore.fetchCatalogue()
    }

    private func refreshFromServer() async {
        guard let apiClient = await environment.apiClientIfAvailable() else { return }
        let client = SnapshotClient(apiClient: apiClient, localStore: environment.localStore)
        do {
            entries = try await client.fetch()
            refreshError = nil
        } catch {
            refreshError = "\(error)"
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
