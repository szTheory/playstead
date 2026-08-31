import Foundation

enum AdapterInstallError: Error, Equatable {
    case digestMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case expansionFailed(String)
    case executableNotFound
}

/// How an installation came to be on disk — the fact that decides which
/// digest could ever have been checked against the pin.
enum AdapterProvenance: String, Equatable {
    /// Downloaded from the pin's own `download_url`, with the downloaded
    /// **archive**'s digest checked against `AdapterPin.sha256` before
    /// anything was expanded. This is the supply-chain proof.
    case pinnedRelease
    /// The user pointed at an application bundle they already had. There
    /// is no archive in this path, so nothing can be compared against
    /// `AdapterPin.sha256` — the interface must not claim otherwise.
    case userSelected
}

/// One row of `adapter_installations`.
///
/// **Two digests, deliberately distinct** — conflating them is the exact
/// defect this shape exists to make impossible:
///
/// * `archiveSHA256` is the digest of the downloaded *release archive*,
///   and it is the only value `AdapterPin.sha256` is ever compared
///   against. It exists only for `.pinnedRelease`.
/// * `executableSHA256` is the digest of the *expanded executable file*
///   this installation actually launches. It is recorded here at
///   install/select time and re-hashed on every single launch by
///   `AdapterHost.verifyInstalledDigest()`.
///
/// The two are different byte streams and can never compare equal; any
/// code that checks one against the other is a bug.
struct AdapterInstallation: Equatable {
    let emulator: String
    let version: String
    let executablePath: String
    /// Digest of the downloaded release archive, already checked against
    /// `AdapterPin.sha256`. `nil` for a user-selected installation, which
    /// never had an archive.
    let archiveSHA256: String?
    /// Digest of the resolved executable on disk — the baseline every
    /// later launch re-hashes against.
    let executableSHA256: String
    let provenance: AdapterProvenance
    /// Whether this installation carries a usable integrity baseline:
    /// its executable digest was recorded, and (for `.pinnedRelease`) the
    /// archive it came from matched the pin. This is **not** a claim that
    /// a user-selected build *is* the pinned build — `provenance` says
    /// that, and the capability card renders it.
    let verified: Bool
}

/// The install state `AdapterHost` consults before every launch —
/// `AdapterInstaller`/`AdapterCatalog`'s selection flow populates this so
/// launch can refuse with a typed error rather than a failed process
/// spawn.
enum AdapterInstallState: Equatable {
    case notInstalled
    case installed(executablePath: String, verified: Bool)
}

/// Downloads and expands the pinned adapter release into
/// `emulators/<emulator>/<version>/`, verifying its digest before ever
/// trusting it, and records exactly one installation row per
/// (emulator, version) — concurrent or repeat install requests converge
/// on that one row via the table's own unique index, and this actor's own
/// serial isolation additionally means a request that finds an already-
/// verified installation returns immediately without touching disk again.
///
/// Never removes the quarantine attribute the download receives and
/// never de-quarantines the expanded application — the operating
/// system's evaluation of the separately-published binary is the
/// integrity gate that makes downloading an emulator defensible at all.
actor AdapterInstaller {
    private let pin: AdapterPin
    private let emulatorsRoot: URL
    private let localStore: LocalStore
    /// Downloads `url` to a local file and returns its path. Injectable so
    /// tests never perform a real network request; the production default
    /// streams via `URLSession`.
    private let downloadArchive: (URL) async throws -> URL
    /// Expands a downloaded archive into `destinationDir`, returning the
    /// path to the resulting application bundle. Injectable so tests never
    /// invoke real disk-image tooling; the production default mounts and
    /// `ditto`s the archive exactly as the plan 03-01 spike proved safe.
    private let archiveExpander: (URL, URL) throws -> URL
    private let idGenerator: () -> String
    private let now: () -> Date

    init(
        pin: AdapterPin,
        emulatorsRoot: URL,
        localStore: LocalStore,
        downloadArchive: @escaping (URL) async throws -> URL = AdapterInstaller.defaultDownload,
        archiveExpander: @escaping (URL, URL) throws -> URL = AdapterInstaller.defaultExpand,
        idGenerator: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) {
        self.pin = pin
        self.emulatorsRoot = emulatorsRoot
        self.localStore = localStore
        self.downloadArchive = downloadArchive
        self.archiveExpander = archiveExpander
        self.idGenerator = idGenerator
        self.now = now
    }

    private var emulatorDirectory: URL {
        emulatorsRoot
            .appendingPathComponent(pin.emulator, isDirectory: true)
            .appendingPathComponent(pin.version, isDirectory: true)
    }

    private var installVerifyURL: URL {
        emulatorDirectory.appendingPathComponent(".install-verify.json")
    }

    /// Installs the pinned adapter, reusing an existing verified
    /// installation with no additional disk activity. Refuses to install
    /// on any digest mismatch, leaving no files behind.
    func install() async throws -> AdapterInstallation {
        // A cached "verified" row means nothing if the expanded .app is
        // no longer on disk (deleted by the user or another process
        // after a prior successful install) — without this check,
        // install() would report success/"already installed" to a
        // caller treating its return value as "ready to play," even
        // though nothing is actually there (P2-WR-001).
        if let existing = existingInstallation(), existing.verified,
           FileManager.default.fileExists(atPath: existing.executablePath) {
            return existing
        }

        let archiveURL = try await downloadArchive(pin.downloadURL)
        // Supply-chain check: the pin's digest describes the published
        // *archive*, so this — and only this — is what it is compared
        // against. Nothing is expanded until it passes.
        let archiveDigest = try hashFile(archiveURL)
        guard archiveDigest == pin.sha256 else {
            try? FileManager.default.removeItem(at: archiveURL)
            throw AdapterInstallError.digestMismatch(expected: pin.sha256, actual: archiveDigest)
        }

        try FileManager.default.createDirectory(at: emulatorDirectory, withIntermediateDirectories: true)
        let appURL: URL
        do {
            appURL = try archiveExpander(archiveURL, emulatorDirectory)
        } catch let error as AdapterInstallError {
            try? FileManager.default.removeItem(at: archiveURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: archiveURL)
            throw AdapterInstallError.expansionFailed("\(error)")
        }
        try? FileManager.default.removeItem(at: archiveURL)

        let executableURL = appURL.appendingPathComponent(pin.launch.executableRelativePath)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw AdapterInstallError.executableNotFound
        }

        // Integrity baseline: the *expanded executable*'s own digest,
        // computed after expansion. This is a different byte stream from
        // the archive above, and it is what every subsequent launch
        // re-hashes and compares against.
        let executableDigest = try hashFile(executableURL)

        let installation = AdapterInstallation(
            emulator: pin.emulator, version: pin.version,
            executablePath: executableURL.path,
            archiveSHA256: archiveDigest, executableSHA256: executableDigest,
            provenance: .pinnedRelease, verified: true
        )
        try recordInstallation(installation)
        writeInstallVerifyRecord(for: installation)
        return installation
    }

    /// Registers an existing installation the user already has at
    /// `appURL` (an application bundle they select) without downloading
    /// anything, recording the resolved executable's own digest as this
    /// installation's integrity baseline.
    ///
    /// There is no archive in this path, so `AdapterPin.sha256` — which
    /// describes the published *archive* — has nothing here to be
    /// compared against, and comparing it to an executable digest would
    /// be a category error that can never succeed. The installation is
    /// therefore recorded with `provenance == .userSelected` and a valid
    /// integrity baseline: launch re-hashes the very bytes the user
    /// chose, and the capability card states plainly that this build was
    /// never verified against the pinned release, so the pinned build's
    /// support claims are not restated for it.
    func selectExisting(appURL: URL) throws -> AdapterInstallation {
        let executableURL = appURL.appendingPathComponent(pin.launch.executableRelativePath)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw AdapterInstallError.executableNotFound
        }
        let executableDigest = try hashFile(executableURL)
        let installation = AdapterInstallation(
            emulator: pin.emulator, version: pin.version,
            executablePath: executableURL.path,
            archiveSHA256: nil, executableSHA256: executableDigest,
            provenance: .userSelected, verified: true
        )
        try recordInstallation(installation)
        writeInstallVerifyRecord(for: installation)
        return installation
    }

    /// The recorded installation for this pin, if any — the composition
    /// root reads this at launch so an install performed in a previous
    /// session is restored rather than silently forgotten.
    func currentInstallation() -> AdapterInstallation? {
        existingInstallation()
    }

    private func existingInstallation() -> AdapterInstallation? {
        Self.recordedInstallation(pin: pin, localStore: localStore)
    }

    /// Reads the recorded installation row without entering the actor — a
    /// pure local read, so the composition root can restore install state
    /// synchronously while it is still assembling itself.
    nonisolated static func recordedInstallation(pin: AdapterPin, localStore: LocalStore) -> AdapterInstallation? {
        let rows = (try? localStore.connection.query(
            """
            SELECT executable_path, sha256, archive_sha256, provenance, verified
            FROM adapter_installations WHERE emulator = ? AND version = ?;
            """,
            params: [pin.emulator, pin.version]
        ) { row -> AdapterInstallation in
            AdapterInstallation(
                emulator: pin.emulator,
                version: pin.version,
                executablePath: row.string(0) ?? "",
                archiveSHA256: row.string(2),
                executableSHA256: row.string(1) ?? "",
                provenance: AdapterProvenance(rawValue: row.string(3) ?? "") ?? .pinnedRelease,
                verified: (row.int(4) ?? 0) != 0
            )
        }) ?? []
        return rows.first
    }

    private func recordInstallation(_ installation: AdapterInstallation) throws {
        try localStore.connection.execute(
            """
            INSERT INTO adapter_installations
                (id, emulator, version, executable_path, sha256, archive_sha256, provenance, verified, installed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(emulator, version) DO UPDATE SET
                executable_path = excluded.executable_path,
                sha256 = excluded.sha256,
                archive_sha256 = excluded.archive_sha256,
                provenance = excluded.provenance,
                verified = excluded.verified,
                installed_at = excluded.installed_at;
            """,
            params: [
                idGenerator(), pin.emulator, pin.version, installation.executablePath,
                installation.executableSHA256, installation.archiveSHA256,
                installation.provenance.rawValue,
                installation.verified ? 1 : 0, ISO8601DateFormatter().string(from: now())
            ]
        )
    }

    /// Mirrors the installation's two digests into the on-disk record
    /// `AdapterHost` falls back to when no install state has been handed
    /// to it in this process (a cold start that has not yet restored one).
    private func writeInstallVerifyRecord(for installation: AdapterInstallation) {
        try? FileManager.default.createDirectory(at: emulatorDirectory, withIntermediateDirectories: true)
        let record = InstallVerifyRecord(
            archiveSHA256: installation.archiveSHA256,
            executableSHA256: installation.executableSHA256,
            executablePath: installation.executablePath
        )
        try? JSONEncoder().encode(record).write(to: installVerifyURL)
    }

    private func hashFile(_ url: URL) throws -> String {
        var hasher = try StreamingSHA256.resume(from: url)
        return hasher.finalizeHex()
    }

    // MARK: - Production defaults

    /// Streams `url` to a private temporary file via `URLSession` and
    /// returns its path. Production default — tests always inject a
    /// local-file substitute instead.
    static func defaultDownload(_ url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw AdapterInstallError.downloadFailed("unexpected response")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// Mounts a disk-image archive read-only, copies its one `.app` into
    /// `destinationDir` with `ditto` (which preserves extended
    /// attributes, including the quarantine flag — unlike a plain copy),
    /// and always detaches the mount afterward. Never strips or rewrites
    /// any extended attribute.
    static func defaultExpand(archiveURL: URL, destinationDir: URL) throws -> URL {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-quiet"]
            try? detach.run()
            _ = waitWithTimeout(detach, seconds: 30)
            try? fm.removeItem(at: mountPoint)
        }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", archiveURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet", "-readonly"]
        try attach.run()
        guard waitWithTimeout(attach, seconds: 60) else {
            throw AdapterInstallError.expansionFailed("timed out waiting for disk image attach")
        }
        guard attach.terminationStatus == 0 else {
            throw AdapterInstallError.expansionFailed("disk image attach failed")
        }

        let contents = try fm.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        guard let appSource = contents.first(where: { $0.pathExtension == "app" }) else {
            throw AdapterInstallError.expansionFailed("no application bundle found in archive")
        }

        let destApp = destinationDir.appendingPathComponent(appSource.lastPathComponent)
        try? fm.removeItem(at: destApp)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = [appSource.path, destApp.path]
        try ditto.run()
        guard waitWithTimeout(ditto, seconds: 60) else {
            ditto.terminate()
            throw AdapterInstallError.expansionFailed("timed out copying into managed storage")
        }
        guard ditto.terminationStatus == 0 else {
            throw AdapterInstallError.expansionFailed("copy into managed storage failed")
        }

        return destApp
    }

    /// Waits for `process` to exit, up to `seconds`. Returns `false` (and
    /// force-terminates the process) if it is still running once the
    /// deadline passes, instead of blocking the actor-isolated
    /// `install()` call indefinitely — `hdiutil attach` against a
    /// downloaded disk image can hang (an unexpected password prompt, a
    /// stuck kernel extension, or a malformed-but-not-corrupt-by-digest
    /// image) with no other way for a caller to cancel or time out
    /// (P2-WR-004).
    private static func waitWithTimeout(_ process: Process, seconds: TimeInterval) -> Bool {
        // A process that never launched (e.g. a `try?`-swallowed `run()`
        // failure) or that already exited before this call has
        // `isRunning == false` — nothing to wait for, and no
        // `terminationHandler` will ever fire for a process that was
        // never started.
        guard process.isRunning else { return true }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        let result = semaphore.wait(timeout: .now() + seconds)
        process.terminationHandler = nil
        if result == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 5)
            return false
        }
        return true
    }
}
