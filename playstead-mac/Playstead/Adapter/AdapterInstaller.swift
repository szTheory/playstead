import Foundation

enum AdapterInstallError: Error, Equatable {
    case digestMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case expansionFailed(String)
    case executableNotFound
}

/// One row of `adapter_installations`: where the resolved executable
/// lives, its own computed digest, and whether that digest matches the
/// pin. `verified == false` is a legal, presented state — a user may
/// select a different build; the interface just has to say so honestly.
struct AdapterInstallation: Equatable {
    let emulator: String
    let version: String
    let executablePath: String
    let sha256: String
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
        let digest = try hashFile(archiveURL)
        guard digest == pin.sha256 else {
            try? FileManager.default.removeItem(at: archiveURL)
            throw AdapterInstallError.digestMismatch(expected: pin.sha256, actual: digest)
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

        try recordInstallation(executablePath: executableURL.path, sha256: digest, verified: true)
        try? JSONEncoder().encode(InstallVerifyRecord(sha256: digest)).write(to: installVerifyURL)

        return AdapterInstallation(
            emulator: pin.emulator, version: pin.version,
            executablePath: executableURL.path, sha256: digest, verified: true
        )
    }

    /// Registers an existing installation the user already has at
    /// `appURL` (an `.app` bundle they select) without downloading
    /// anything. Computes the resolved executable's own digest and
    /// records whether it matches the pin — a mismatch is recorded, not
    /// rejected: the user may use a different build, but the interface
    /// has to say so rather than presenting the same support claim for a
    /// different binary.
    func selectExisting(appURL: URL) throws -> AdapterInstallation {
        let executableURL = appURL.appendingPathComponent(pin.launch.executableRelativePath)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw AdapterInstallError.executableNotFound
        }
        let digest = try hashFile(executableURL)
        let verified = digest == pin.sha256
        try recordInstallation(executablePath: executableURL.path, sha256: digest, verified: verified)
        return AdapterInstallation(
            emulator: pin.emulator, version: pin.version,
            executablePath: executableURL.path, sha256: digest, verified: verified
        )
    }

    private func existingInstallation() -> AdapterInstallation? {
        let rows = (try? localStore.connection.query(
            "SELECT executable_path, sha256, verified FROM adapter_installations WHERE emulator = ? AND version = ?;",
            params: [pin.emulator, pin.version]
        ) { row -> AdapterInstallation in
            AdapterInstallation(
                emulator: self.pin.emulator,
                version: self.pin.version,
                executablePath: row.string(0) ?? "",
                sha256: row.string(1) ?? "",
                verified: (row.int(2) ?? 0) != 0
            )
        }) ?? []
        return rows.first
    }

    private func recordInstallation(executablePath: String, sha256: String, verified: Bool) throws {
        try localStore.connection.execute(
            """
            INSERT INTO adapter_installations
                (id, emulator, version, executable_path, sha256, verified, installed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(emulator, version) DO UPDATE SET
                executable_path = excluded.executable_path,
                sha256 = excluded.sha256,
                verified = excluded.verified,
                installed_at = excluded.installed_at;
            """,
            params: [
                idGenerator(), pin.emulator, pin.version, executablePath, sha256,
                verified ? 1 : 0, ISO8601DateFormatter().string(from: now())
            ]
        )
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
            detach.waitUntilExit()
            try? fm.removeItem(at: mountPoint)
        }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", archiveURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet", "-readonly"]
        try attach.run()
        attach.waitUntilExit()
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
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw AdapterInstallError.expansionFailed("copy into managed storage failed")
        }

        return destApp
    }
}
