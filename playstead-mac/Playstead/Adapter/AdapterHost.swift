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

    init(pin: AdapterPin, emulatorsRoot: URL) {
        self.pin = pin
        self.emulatorsRoot = emulatorsRoot
    }

    private var emulatorDirectory: URL {
        emulatorsRoot
            .appendingPathComponent(pin.emulator, isDirectory: true)
            .appendingPathComponent(pin.version, isDirectory: true)
    }

    /// The resolved path to the pinned emulator's executable under the
    /// cache root's `emulators/` directory.
    var executableURL: URL {
        emulatorDirectory.appendingPathComponent(pin.launch.executableRelativePath)
    }

    private var installVerifyURL: URL {
        emulatorDirectory.appendingPathComponent(".install-verify.json")
    }

    /// Confirms the emulator directory's recorded install-time digest
    /// still matches `pin.sha256`. Throws on any mismatch or missing
    /// record — a typed error the UI can render as a remedy, not a
    /// silent fallback to "launch anyway".
    func verifyInstalledDigest() throws {
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
        proc.executableURL = executableURL
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
