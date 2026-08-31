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

    init() {
        let paths = AppPaths()
        self.appPaths = paths
        let store = (try? LocalStore(paths: paths)) ?? LocalStore.inMemoryFallback()
        self.localStore = store
        self.controllerMappingStore = ControllerMappingStore(localStore: store)
        self.biosStore = BiosStore(localStore: store, managedDirectory: paths.bios, references: [])
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

        // Wires ControllerHost's connect/disconnect/assign transitions to
        // AdapterHost's launch arguments — without this, a remap or a
        // reconnect never reaches the emulator (P2-CR-003).
        controllerHost.onAssignmentChanged = { [weak self] in self?.refreshActiveControllerMapping() }
        // A controller already connected before the window opens (D-14)
        // must have its mapping applied immediately, not only on the next
        // connect/disconnect/assign transition.
        refreshActiveControllerMapping()
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
