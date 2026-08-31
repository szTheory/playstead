import Foundation

/// A cheap-check verify record for one committed cache object: the
/// attributes `PreflightChecker` compares against disk state before
/// falling back to a full re-hash (CACH-04's zero-network contract).
struct VerifyRecord: Equatable, Codable {
    let sha256: String
    let size: Int
    let inode: UInt64
    let mtime: Double
}

enum CASError: Error, Equatable {
    case digestAlreadyExists
    case sourceMissing
}

/// Mirrors the server's content-addressed layout from D-20: an object
/// for digest `d` lives at `objects/<d[0..1]>/<d[2..3]>/<d>`. Owns the
/// commit/quarantine boundary between an unverified `.partial` file and
/// a trusted cache object — nothing outside this type ever writes
/// directly into `objects/`.
final class CASManager {
    let paths: AppPaths
    private let verifyIndexURL: URL
    private let queue = DispatchQueue(label: "dev.playstead.mac.cas")

    init(paths: AppPaths) {
        self.paths = paths
        self.verifyIndexURL = paths.objects.appendingPathComponent("verify-index.json")
    }

    func objectURL(for sha256: String) -> URL {
        paths.objectURL(for: sha256)
    }

    func contains(_ sha256: String) -> Bool {
        FileManager.default.fileExists(atPath: objectURL(for: sha256).path)
    }

    /// Atomically renames a verified partial file into the CAS at its
    /// digest-derived path. The caller is responsible for verifying the
    /// partial's full-stream SHA-256 equals `sha256` before calling this
    /// — `CASManager` trusts that contract and only handles placement.
    /// If an object with this digest is already committed (a concurrent
    /// or repeat download of the same content), the redundant partial is
    /// discarded and this is treated as success — content-addressing
    /// makes the two byte-identical by construction.
    func commit(partialAt partialURL: URL, sha256: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: partialURL.path) else {
            throw CASError.sourceMissing
        }

        let dest = objectURL(for: sha256)
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: partialURL)
        } else {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                // `objects/` and `partials/` both live under the same
                // cache root filesystem, so this is a same-volume
                // rename — atomic, no partial-write window a crash
                // could observe.
                try fm.moveItem(at: partialURL, to: dest)
            } catch {
                // TOCTOU: two concurrent commits of the same digest can
                // both observe `fileExists == false` above, and the
                // loser's move then fails because the winner already
                // placed the object. Content-addressing guarantees the
                // bytes are identical, so treat "destination now exists"
                // as success rather than propagating the error
                // (P1-WR-002).
                guard fm.fileExists(atPath: dest.path) else { throw error }
                try? fm.removeItem(at: partialURL)
            }
        }

        try recordVerify(for: sha256, at: dest)
    }

    /// Moves a failed partial aside without deleting it — evidence for
    /// diagnosing a corrupt transfer stays on disk rather than vanishing
    /// silently.
    func quarantine(partialAt partialURL: URL, reason: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: partialURL.path) else { return }

        let quarantineDir = paths.partials.appendingPathComponent("quarantine", isDirectory: true)
        try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let dest = quarantineDir.appendingPathComponent("\(partialURL.lastPathComponent).\(stamp)")
        try fm.moveItem(at: partialURL, to: dest)

        let reasonURL = dest.appendingPathExtension("reason.txt")
        try? reason.write(to: reasonURL, atomically: true, encoding: .utf8)
    }

    func verifyRecord(for sha256: String) -> VerifyRecord? {
        loadIndex()[sha256]
    }

    /// Deletes the committed object for `sha256` and its verify-index
    /// entry. The only caller in this codebase is
    /// `EvictionPlanner.execute(_:)`, acting on an explicit, user-
    /// confirmed plan — nothing outside this type ever writes (or
    /// removes) directly under `objects/` (plan 03-07 task 3).
    func remove(_ sha256: String) throws {
        let url = objectURL(for: sha256)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        queue.sync {
            var index = loadIndexUnlocked()
            index.removeValue(forKey: sha256)
            saveIndexUnlocked(index)
        }
    }

    private func recordVerify(for sha256: String, at objectURL: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: objectURL.path)
        let size = (attrs[.size] as? Int) ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0

        let record = VerifyRecord(sha256: sha256, size: size, inode: inode, mtime: mtime)
        queue.sync {
            var index = loadIndexUnlocked()
            index[sha256] = record
            saveIndexUnlocked(index)
        }
    }

    private func loadIndex() -> [String: VerifyRecord] {
        queue.sync { loadIndexUnlocked() }
    }

    private func loadIndexUnlocked() -> [String: VerifyRecord] {
        guard let data = try? Data(contentsOf: verifyIndexURL) else { return [:] }
        return (try? JSONDecoder().decode([String: VerifyRecord].self, from: data)) ?? [:]
    }

    private func saveIndexUnlocked(_ index: [String: VerifyRecord]) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: verifyIndexURL, options: .atomic)
    }
}
