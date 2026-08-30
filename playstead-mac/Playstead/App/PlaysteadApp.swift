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

    var body: some Scene {
        WindowGroup {
            LibraryShellView()
                .environment(appEnvironment)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}

/// Shared, observable app-wide dependencies constructed once at launch.
/// Kept intentionally small in this tracer plan: a local store, an API
/// client (nil until a paired credential exists), and the cache root.
@Observable
final class AppEnvironment {
    let appPaths: AppPaths
    let localStore: LocalStore
    private(set) var apiClient: APIClient?

    init() {
        let paths = AppPaths()
        self.appPaths = paths
        self.localStore = (try? LocalStore(paths: paths)) ?? LocalStore.inMemoryFallback()
        self.apiClient = APIClient(keychain: KeychainStore())
    }
}
