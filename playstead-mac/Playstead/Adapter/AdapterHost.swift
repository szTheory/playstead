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
            guard FileManager.default.fileExists(atPath: path) else {
                throw LaunchError.emulatorNotInstalled
            }
            guard verified else {
                throw LaunchError.digestMismatch(expected: pin.sha256, actual: "unverified-selection")
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
        proc.arguments = pin.launch.renderedArguments(romPath: romPath, saveDir: saveDir)

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
