import Foundation

/// Centralises every on-disk location the client owns (D-20).
///
/// The cache root lives under `~/Library/Application Support/Playstead/`,
/// never `~/Library/Caches/` — Caches is OS-purgeable under disk pressure,
/// which would silently break the "verified locally cached game stays
/// launchable offline" promise (CACH-04). The directory is marked
/// excluded from Time Machine / iCloud backup on first creation: cache
/// objects are re-downloadable, not something a backup needs to carry.
struct AppPaths {
    let root: URL
    let objects: URL
    let partials: URL
    let launch: URL
    let emulators: URL
    let bios: URL
    let databaseURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("Playstead", isDirectory: true)
        self.init(root: root, fileManager: fileManager)
    }

    /// Test-only / advanced entry point: builds the same directory
    /// layout under an arbitrary `root` rather than the real Application
    /// Support directory, so cache/download tests never touch a real
    /// user's on-disk state.
    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.objects = root.appendingPathComponent("objects", isDirectory: true)
        self.partials = root.appendingPathComponent("partials", isDirectory: true)
        self.launch = root.appendingPathComponent("launch", isDirectory: true)
        self.emulators = root.appendingPathComponent("emulators", isDirectory: true)
        self.bios = root.appendingPathComponent("bios", isDirectory: true)
        self.databaseURL = root.appendingPathComponent("playstead.sqlite3", isDirectory: false)

        createDirectoriesIfNeeded(fileManager: fileManager)
        // Clear first so a stale root-level `true` (the pre-D-63 shape,
        // which inherited down to `saves/` and `playstead.sqlite3`) can
        // never re-inherit onto a directory whose own flag is being
        // written in the same pass below.
        clearStaleRootBackupExclusion(fileManager: fileManager)
        excludeReconstructableDirectoriesFromBackup(fileManager: fileManager)
    }

    private func createDirectoriesIfNeeded(fileManager: FileManager) {
        for dir in [root, objects, partials, launch, emulators, bios] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Sets `isExcludedFromBackup = true` on exactly the five
    /// reconstructable cache directories — never on `root`, and never on
    /// `saves/`. Cache objects are re-derivable from the server and must
    /// never occupy a user's backup budget or be represented in Time
    /// Machine as durable user data (D-20). `saves/` is deliberately
    /// absent from this list: it becomes Time-Machine-eligible by
    /// omission rather than by an explicit `false` write, because it
    /// (along with `playstead.sqlite3`, a sibling of `root`) holds the
    /// only bytes on the machine that cannot be re-derived from the
    /// server (D-63).
    private func excludeReconstructableDirectoriesFromBackup(fileManager: FileManager) {
        for dir in [objects, partials, launch, emulators, bios] {
            var mutableDir = dir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutableDir.setResourceValues(resourceValues)
        }
    }

    /// Migration path for installs shipped before D-63: the previous
    /// implementation set `isExcludedFromBackup = true` on `root`, which
    /// inherits to the entire subtree, including `saves/` and
    /// `playstead.sqlite3` — the only irreplaceable bytes on the
    /// machine. Reads the root's current flag and, only when it is
    /// `true`, writes `false`. Safe to call on every launch: when the
    /// flag is already `false` or absent, this performs no write and
    /// returns without error, so repeated calls are idempotent.
    private func clearStaleRootBackupExclusion(fileManager: FileManager) {
        guard let currentValue = try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
              currentValue == true
        else {
            return
        }
        var mutableRoot = root
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        try? mutableRoot.setResourceValues(resourceValues)
    }

    /// The content-addressed path for an object with digest `sha256`,
    /// mirroring the server's CAS layout: `objects/<aa>/<bb>/<sha256>`.
    ///
    /// `sha256` originates from the paired server's catalogue JSON, so it
    /// is validated as a 64-character lowercase hex digest before it is
    /// spliced into a path component (CR-02). Without that check a server
    /// could hand back `"../../../../Library/LaunchAgents/evil"` and have
    /// `CASManager.commit` move a downloaded payload there — and the
    /// digest check is no backstop, because the payload is only verified
    /// to hash to that same attacker-chosen string.
    ///
    /// This throws rather than returning `URL?` so the rejected value
    /// travels with the error to whichever layer decides what to do, and
    /// so no call site can collapse the failure into an unsafe fallback
    /// path with `??`.
    func objectURL(for sha256: String) throws -> URL {
        try PathSafety.validatedDigest(sha256)
        let a = String(sha256.prefix(2))
        let b = String(sha256.dropFirst(2).prefix(2))
        return objects.appendingPathComponent(a).appendingPathComponent(b).appendingPathComponent(sha256)
    }

    /// The in-progress download path for `sha256`, held flat under
    /// `partials/`. Validated identically to `objectURL(for:)` — the raw
    /// string is used as a single path component, so an unvalidated one
    /// escapes `partials/` just as easily (CR-02).
    func partialURL(for sha256: String) throws -> URL {
        try PathSafety.validatedDigest(sha256)
        return partials.appendingPathComponent(sha256)
    }

    /// The materialized launch directory for one asset set.
    func launchDirectory(forAssetSet id: String) -> URL {
        launch.appendingPathComponent(id, isDirectory: true)
    }
}
