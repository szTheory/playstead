import Foundation
import AppKit

/// Recorded once at emulator install time (a later plan's job — this
/// tracer plan does not build the installer) and re-checked on every
/// launch by `AdapterHost.verifyInstalledDigest()`. The spike proved
/// the binary once; the app re-proves it every time.
struct InstallVerifyRecord: Codable, Equatable {
    let sha256: String
}

/// Keeps every launched emulator process terminated when the app quits,
/// so a launched process never outlives (and is never orphaned by) the
/// app that started it.
final class AdapterProcessRegistry: @unchecked Sendable {
    static let shared = AdapterProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var observing = false

    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        ensureObservingLocked()
        lock.unlock()
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    private func ensureObservingLocked() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.terminateAll()
        }
    }

    private func terminateAll() {
        lock.lock()
        let procs = Array(processes.values)
        lock.unlock()
        for proc in procs where proc.isRunning {
            proc.terminate()
        }
    }
}

/// Launches the pinned emulator via Foundation `Process` and observes
/// its exit. Every consumer-facing value (executable path, argument
/// template, exit signatures) comes from `AdapterPin` — no emulator
/// version, flag, or config key is a literal here.
///
/// Never removes the quarantine attribute from the emulator and never
/// copies it into the app bundle: the operating system's Gatekeeper
/// evaluation of a separately notarized binary is the integrity gate;
/// suppressing it would both defeat that gate and read as malware
/// behaviour (D-05).
actor AdapterHost {
    enum LaunchError: Error, Equatable {
        case emulatorNotInstalled
        case digestMismatch(expected: String, actual: String)
    }

    private let pin: AdapterPin
    private let emulatorsRoot: URL
    private var process: Process?

    /// The install state resolved by `AdapterInstaller`/`AdapterCatalog`'s
    /// selection flow (plan 03-09). Defaults to `.notInstalled`, which
    /// preserves this type's original fixed-directory digest check below
    /// unchanged for any caller that never sets it.
    private var installState: AdapterInstallState = .notInstalled

    /// The controller mapping `ControllerSettingsView`/`ControllerHost`
    /// currently have active for the assigned controller, injected into
    /// every subsequent launch's rendered arguments. `nil` (the default)
    /// launches with no controller-mapping override at all — a mapping
    /// the emulator never reads would look correct in settings and do
    /// nothing in the game, so this is read directly by
    /// `renderedLaunchArguments`, the same method the test suite asserts
    /// against (plan 03-10).
    private var activeControllerMapping: ControllerMapping?

    init(pin: AdapterPin, emulatorsRoot: URL) {
        self.pin = pin
        self.emulatorsRoot = emulatorsRoot
    }

    /// Records which installation (downloaded or user-selected) launch
    /// should trust. Passing `.installed(_, verified: false)` makes every
    /// subsequent launch attempt fail with a typed `digestMismatch`
    /// rather than a failed process spawn.
    func setInstallState(_ state: AdapterInstallState) {
        installState = state
    }

    /// Sets (or clears, with `nil`) the controller mapping every
    /// subsequent `launch` injects. `ControllerHost`/`ControllerSettingsView`
    /// call this whenever the assigned controller or its mapping
    /// changes.
    func setControllerMapping(_ mapping: ControllerMapping?) {
        activeControllerMapping = mapping
    }

    /// Builds the exact argument array `launch(...)` hands to `Process`
    /// — pure and independently testable, so a test can assert the
    /// injected configuration contains the active mapping's values
    /// without spawning a real process.
    ///
    /// Renders the pin's own launch template first (unchanged
    /// behaviour), then appends one `cli_config_override` pair per
    /// mapped input. The pinned mGBA build's `config_injection.keys`
    /// records `controller_mapping` as `"not_probed_no_hardware_available"`
    /// (03-ADAPTER-PIN.json) — the spike never had hardware to confirm a
    /// real per-button flag syntax — so this falls back to mGBA's own
    /// documented general `-C key=value` override mechanism (the same
    /// flag the pin already uses for `savegamePath`), under an
    /// `input.<adapterInput>` key. Whether mGBA's runtime actually reads
    /// that specific key name is therefore unverified pending real
    /// controller hardware; the wiring itself — that the active mapping
    /// reaches the injected configuration at launch — is what this
    /// method and its test prove.
    func renderedLaunchArguments(romPath: String, saveDir: String) -> [String] {
        var args = pin.launch.renderedArguments(romPath: romPath, saveDir: saveDir)
        guard let mapping = activeControllerMapping else { return args }
        for input in mapping.mappings {
            args.append("-C")
            args.append("input.\(input.adapterInput)=\(input.controllerInput)")
        }
        return args
    }

    private var emulatorDirectory: URL {
        emulatorsRoot
            .appendingPathComponent(pin.emulator, isDirectory: true)
            .appendingPathComponent(pin.version, isDirectory: true)
    }

    /// The resolved path to the pinned emulator's executable under the
    /// cache root's `emulators/` directory. When `installState` names a
    /// different (e.g. user-selected) path, `resolvedExecutableURL` below
    /// is what launch actually uses — this property stays the fixed
    /// downloaded-install location for backward compatibility and for the
    /// `.notInstalled` fallback path.
    var executableURL: URL {
        emulatorDirectory.appendingPathComponent(pin.launch.executableRelativePath)
    }

    /// The executable launch actually uses: the install state's own path
    /// when one has been set, otherwise the fixed downloaded-install
    /// location.
    private var resolvedExecutableURL: URL {
        if case .installed(let path, _) = installState {
            return URL(fileURLWithPath: path)
        }
        return executableURL
    }

    private var installVerifyURL: URL {
        emulatorDirectory.appendingPathComponent(".install-verify.json")
    }

    /// Confirms the resolved installation is present and verified before
    /// every launch — a typed error the UI can render as a remedy, not a
    /// silent fallback to "launch anyway". When `installState` was set
    /// explicitly (by `AdapterInstaller`'s download or selection flow),
    /// that state is authoritative. Otherwise this falls back to reading
    /// the on-disk `.install-verify.json` record at the fixed downloaded-
    /// install location, exactly as before this plan (03-09) added
    /// `installState`.
    func verifyInstalledDigest() throws {
        if case .installed(let path, let verified) = installState {
            // The verified flag is a fact already established at
            // install/selection time — check it first, so an explicitly
            // unverified installation always reports as a digest
            // mismatch rather than being masked by an unrelated
            // "file not found" if its path also happens not to resolve.
            guard verified else {
                throw LaunchError.digestMismatch(expected: pin.sha256, actual: "unverified-selection")
            }
            guard FileManager.default.fileExists(atPath: path) else {
                throw LaunchError.emulatorNotInstalled
            }
            return
        }

        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw LaunchError.emulatorNotInstalled
        }
        guard
            let data = try? Data(contentsOf: installVerifyURL),
            let record = try? JSONDecoder().decode(InstallVerifyRecord.self, from: data)
        else {
            throw LaunchError.digestMismatch(expected: pin.sha256, actual: "unrecorded")
        }
        guard record.sha256 == pin.sha256 else {
            throw LaunchError.digestMismatch(expected: pin.sha256, actual: record.sha256)
        }
    }

    /// Launches the emulator against a materialized ROM path and an
    /// app-managed save directory, invoking `onExit` exactly once when
    /// the process terminates (clean/crashed/killed/unknown, per the
    /// pin's `exitDetection` table).
    @discardableResult
    func launch(
        romPath: String,
        saveDir: String,
        onExit: @escaping @Sendable (AdapterExit) -> Void
    ) throws -> Process {
        try verifyInstalledDigest()

        let proc = Process()
        proc.executableURL = resolvedExecutableURL
        proc.arguments = renderedLaunchArguments(romPath: romPath, saveDir: saveDir)

        let detection = pin.exitDetection
        let registry = AdapterProcessRegistry.shared
        proc.terminationHandler = { finished in
            registry.unregister(finished)
            let exit = AdapterExit.classify(
                status: finished.terminationStatus,
                reason: finished.terminationReason,
                against: detection
            )
            onExit(exit)
        }

        try proc.run()
        process = proc
        registry.register(proc)
        return proc
    }

    /// Requests termination of the currently running process, if any.
    func terminateIfRunning() {
        process?.terminate()
    }
}
