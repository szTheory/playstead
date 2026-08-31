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
/// client (nil until a paired credential exists), the cache/download/
/// preflight layer, and the adapter host once the pin loads.
@Observable
final class AppEnvironment {
    let appPaths: AppPaths
    let localStore: LocalStore
    let casManager: CASManager
    let preflightChecker: PreflightChecker
    let launchMaterializer: LaunchMaterializer
    private(set) var apiClient: APIClient?
    private(set) var adapterHost: AdapterHost?
    private(set) var adapterPinLoadError: Error?

    init() {
        let paths = AppPaths()
        self.appPaths = paths
        self.localStore = (try? LocalStore(paths: paths)) ?? LocalStore.inMemoryFallback()
        self.apiClient = APIClient(keychain: KeychainStore())

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
    }

    func makeDownloadEngine() -> DownloadEngine {
        DownloadEngine(session: URLSession(configuration: .ephemeral), paths: appPaths, cas: casManager)
    }
}
