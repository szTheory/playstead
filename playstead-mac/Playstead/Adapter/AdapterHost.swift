import Foundation
import AppKit

/// Written at install/select time by `AdapterInstaller` and re-checked on
/// every launch by `AdapterHost.verifyInstalledDigest()`. The spike
/// proved the binary once; the app re-proves it every time.
///
/// Carries the installation's **two distinct digests** (see
/// `AdapterInstallation`): the archive digest that was checked against
/// `AdapterPin.sha256` at download time, and the expanded executable's
/// own digest, which is the value a launch re-hashes against. A record
/// written by an older build (which stored a single `sha256` field whose
/// value was the archive digest) fails to decode here and is treated as
/// unrecorded — fail-closed, which forces a re-install rather than
/// trusting an ambiguous digest.
struct InstallVerifyRecord: Codable, Equatable {
    /// `nil` for a user-selected installation, which never had an archive.
    let archiveSHA256: String?
    let executableSHA256: String
    let executablePath: String

    private enum CodingKeys: String, CodingKey {
        case archiveSHA256 = "archive_sha256"
        case executableSHA256 = "executable_sha256"
        case executablePath = "executable_path"
    }
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
        // The pin's own recorded evidence (`AdapterPin.json`'s
        // `exit_detection.clean.note`) documents there is "no observed
        // graceful-quit path from an external Process.terminate() call"
        // for the pinned emulator, and macOS does not block app
        // termination on this notification handler — so a SIGTERM that
        // the child never acts on can otherwise leave an orphaned
        // emulator process running after Playstead itself has quit.
        // Give every still-running process a short grace period, then
        // escalate to SIGKILL (P2-WR-005).
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, procs.contains(where: { $0.isRunning }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        for proc in procs where proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
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

    /// The digest of the *executable* this installation is supposed to
    /// be — recorded by `AdapterInstaller` at install/select time and
    /// re-hashed against the live file on every launch. Never
    /// `pin.sha256`: that digest describes the published archive, a
    /// different byte stream, and comparing the two can never succeed.
    private var expectedExecutableSHA256: String?

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
        expectedExecutableSHA256 = nil
    }

    /// The call site `AdapterInstaller`'s install/select result flows
    /// through: records both the path to launch and the executable digest
    /// every later launch re-hashes against, so the live re-verification
    /// below has something it can actually compare to.
    func setInstallation(_ installation: AdapterInstallation) {
        installState = .installed(
            executablePath: installation.executablePath, verified: installation.verified
        )
        expectedExecutableSHA256 = installation.executableSHA256
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
    /// `biosPath` is the resolved path to a validated, managed BIOS file
    /// for the ROM's system, if one exists (`nil` when no BIOS has been
    /// validated) — passed by the caller, since `AdapterHost` holds no
    /// reference to `BiosStore` itself. When present, renders the pin's
    /// `config_injection.keys["bios_path"]` template (e.g. `"-b {path}"`)
    /// so a validated BIOS is actually used by the emulator rather than
    /// only being described as "in use" by the UI (P2-CR-002).
    func renderedLaunchArguments(romPath: String, saveDir: String, biosPath: String? = nil) -> [String] {
        var args = pin.launch.renderedArguments(romPath: romPath, saveDir: saveDir)
        if let biosPath, let template = pin.configInjection.keys["bios_path"] {
            args.append(contentsOf: template
                .replacingOccurrences(of: "{path}", with: biosPath)
                .split(separator: " ")
                .map(String.init))
        }
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
                throw LaunchError.digestMismatch(
                    expected: expectedExecutableSHA256 ?? "recorded-executable-digest",
                    actual: "unverified-selection"
                )
            }
            guard FileManager.default.fileExists(atPath: path) else {
                throw LaunchError.emulatorNotInstalled
            }
            guard let expected = expectedExecutableSHA256 ?? recordedInstallVerify()?.executableSHA256 else {
                // An install state handed over without an executable
                // digest baseline cannot be re-verified, and launching
                // unverified bytes is exactly what this gate exists to
                // refuse.
                throw LaunchError.digestMismatch(
                    expected: "recorded-executable-digest", actual: "unrecorded"
                )
            }
            try reverifyLiveDigest(at: path, expected: expected)
            return
        }

        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw LaunchError.emulatorNotInstalled
        }
        guard let record = recordedInstallVerify() else {
            throw LaunchError.digestMismatch(expected: pin.sha256, actual: "unrecorded")
        }
        // Supply chain: when this installation came from a download, the
        // archive it was expanded from must still name the pinned
        // release. `pin.sha256` is compared here — against the archive
        // digest — and nowhere else.
        if let archiveDigest = record.archiveSHA256, archiveDigest != pin.sha256 {
            throw LaunchError.digestMismatch(expected: pin.sha256, actual: archiveDigest)
        }
        // Integrity: the cached record only proves the digest matched at
        // some past install/select moment — it says nothing about the
        // bytes currently on disk. Re-hash the live executable every
        // launch, exactly as `InstallVerifyRecord`'s own doc comment
        // promises ("the app re-proves it every time"), so a binary
        // swapped or corrupted after install is caught here instead of
        // trusted forever (P2-CR-001).
        try reverifyLiveDigest(at: executableURL.path, expected: record.executableSHA256)
    }

    private func recordedInstallVerify() -> InstallVerifyRecord? {
        guard let data = try? Data(contentsOf: installVerifyURL) else { return nil }
        return try? JSONDecoder().decode(InstallVerifyRecord.self, from: data)
    }

    /// Re-hashes the file currently on disk at `path` and confirms it
    /// still matches the digest recorded for this installation's
    /// **executable** — the actual "re-proves it every time" check.
    ///
    /// `expected` is deliberately a parameter rather than `pin.sha256`:
    /// the pin's digest describes the published *archive*, so hashing an
    /// expanded executable and comparing it to the pin could never
    /// succeed and made every launch fail with `digestMismatch`. The
    /// archive is still verified against the pin — at download time, in
    /// `AdapterInstaller.install()`, which is where the archive exists.
    private func reverifyLiveDigest(at path: String, expected: String) throws {
        var hasher = try StreamingSHA256.resume(from: URL(fileURLWithPath: path))
        let actualDigest = hasher.finalizeHex()
        guard actualDigest == expected else {
            throw LaunchError.digestMismatch(expected: expected, actual: actualDigest)
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
        biosPath: String? = nil,
        onExit: @escaping @Sendable (AdapterExit) -> Void
    ) throws -> Process {
        try verifyInstalledDigest()

        let proc = Process()
        proc.executableURL = resolvedExecutableURL
        proc.arguments = renderedLaunchArguments(romPath: romPath, saveDir: saveDir, biosPath: biosPath)

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
