import Foundation

/// A candidate could not be validated as a BIOS. `reason` is the exact,
/// no-blame explanation the interface renders — never a generic failure.
enum BiosStoreError: Error, Equatable {
    case invalidCandidate(reason: String)
}

/// One accepted, digest-validated BIOS file in managed storage —
/// `bios_files`'s row shape.
struct BiosRecord: Equatable {
    let sha256: String
    let system: String
    let byteLength: Int
    let managedFilename: String
    let acceptedAt: Date
}

/// Validates a dragged-in BIOS candidate by exact byte length and then, on
/// a length match, by digest against the caller-supplied set of known
/// reference digests for that system — deliberately the same length-
/// then-digest shape as the server import pipeline's reference-match
/// verification (mirrored in spirit, not code: this client's only
/// digest primitive is `StreamingSHA256`, so it compares SHA-256 rather
/// than the server's CRC32/MD5/SHA-1 set), never a bespoke format
/// parser — a parser that claims to recognise a BIOS by inspecting its
/// contents is a new attack surface and a new source of false
/// confidence, whereas a length and a digest are exactly as much as
/// anyone can honestly assert.
///
/// `references` carries no built-in default: this client has never had
/// an opportunity to empirically confirm a real reference digest (the
/// plan 03-01 spike explicitly recorded its BIOS probe as
/// not-run/no-fixture-available, never faked — see 03-SPIKE-REPORT.md),
/// so fabricating one here would silently misrepresent evidence this
/// project has not actually gathered. A caller with a confirmed
/// reference digest supplies it; until then this store correctly and
/// honestly rejects every candidate, which is the safe default for
/// content this product never verifies or acquires on its own.
///
/// This type never provides a source, a hint, or any way to acquire the
/// content it validates — the user either already has the file or does
/// not, and this store's only job is to validate what they have.
final class BiosStore {
    /// The expected shape for one system's BIOS: an exact byte length and
    /// the set of SHA-256 digests that are known-good matches.
    struct Reference: Equatable {
        let system: String
        let expectedByteLength: Int
        let knownSHA256Digests: Set<String>
    }

    private let localStore: LocalStore
    private let managedDirectory: URL
    private let references: [Reference]
    private let now: () -> Date

    init(
        localStore: LocalStore,
        managedDirectory: URL,
        references: [Reference],
        now: @escaping () -> Date = Date.init
    ) {
        self.localStore = localStore
        self.managedDirectory = managedDirectory
        self.references = references
        self.now = now
        try? FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
    }

    /// Validates `candidateURL` and, on acceptance, copies its bytes —
    /// never moves, never modifies — into managed storage under a name
    /// derived from the file's own digest, never the original filename.
    /// Treats `candidateURL` as fully untrusted: a symbolic link is
    /// rejected by inspecting the link itself (never resolving or
    /// opening whatever it points at), a non-regular-file path
    /// (a directory included) is rejected before any open, and the
    /// underlying file is opened strictly read-only, solely to measure
    /// its length and compute its digest.
    @discardableResult
    func validateAndAccept(candidateURL: URL, system: String) throws -> BiosRecord {
        let fm = FileManager.default

        // `destinationOfSymbolicLink` uses `readlink()` — it inspects the
        // link entry itself and never follows or opens whatever it
        // points at, even when the target is missing entirely.
        if (try? fm.destinationOfSymbolicLink(atPath: candidateURL.path)) != nil {
            throw BiosStoreError.invalidCandidate(reason: "symbolic links are not accepted")
        }

        guard let attrs = try? fm.attributesOfItem(atPath: candidateURL.path) else {
            throw BiosStoreError.invalidCandidate(reason: "the file could not be read")
        }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw BiosStoreError.invalidCandidate(reason: "only a single regular file is accepted")
        }

        guard let reference = references.first(where: { $0.system == system }) else {
            throw BiosStoreError.invalidCandidate(reason: "no known reference for this system yet")
        }

        let actualLength = (attrs[.size] as? Int) ?? -1
        guard actualLength == reference.expectedByteLength else {
            throw BiosStoreError.invalidCandidate(
                reason: "wrong size (expected \(reference.expectedByteLength) bytes, got \(actualLength))"
            )
        }

        let digest = try hashFile(candidateURL)
        guard reference.knownSHA256Digests.contains(digest) else {
            throw BiosStoreError.invalidCandidate(reason: "this file's contents don't match a known reference")
        }

        let managedURL = managedDirectory.appendingPathComponent(digest)
        if !fm.fileExists(atPath: managedURL.path) {
            try fm.copyItem(at: candidateURL, to: managedURL)
        }

        let timestamp = now()
        try localStore.connection.execute(
            """
            INSERT INTO bios_files (sha256, system, byte_length, managed_filename, accepted_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(sha256) DO NOTHING;
            """,
            params: [digest, system, actualLength, digest, ISO8601DateFormatter().string(from: timestamp)]
        )

        return BiosRecord(sha256: digest, system: system, byteLength: actualLength, managedFilename: digest, acceptedAt: timestamp)
    }

    /// Removes a managed BIOS by digest. Deletes only the managed copy —
    /// the user's original file, wherever it lives, is never touched by
    /// this type.
    func remove(sha256: String) throws {
        let managedURL = managedDirectory.appendingPathComponent(sha256)
        if FileManager.default.fileExists(atPath: managedURL.path) {
            try FileManager.default.removeItem(at: managedURL)
        }
        try localStore.connection.execute("DELETE FROM bios_files WHERE sha256 = ?;", params: [sha256])
    }

    func hasManagedBIOS(forSystem system: String) -> Bool {
        let rows = (try? localStore.connection.query(
            "SELECT 1 FROM bios_files WHERE system = ? LIMIT 1;", params: [system]
        ) { _ in true }) ?? []
        return !rows.isEmpty
    }

    func managedRecord(forSystem system: String) -> BiosRecord? {
        let rows = (try? localStore.connection.query(
            "SELECT sha256, byte_length, managed_filename, accepted_at FROM bios_files WHERE system = ? LIMIT 1;",
            params: [system]
        ) { row -> BiosRecord in
            BiosRecord(
                sha256: row.string(0) ?? "",
                system: system,
                byteLength: row.int(1) ?? 0,
                managedFilename: row.string(2) ?? "",
                acceptedAt: ISO8601DateFormatter().date(from: row.string(3) ?? "") ?? Date(timeIntervalSince1970: 0)
            )
        }) ?? []
        return rows.first
    }

    func managedPath(forSHA256 sha256: String) -> URL {
        managedDirectory.appendingPathComponent(sha256)
    }

    private func hashFile(_ url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BiosStoreError.invalidCandidate(reason: "the file could not be read")
        }
        defer { try? handle.close() }

        var hasher = StreamingSHA256()
        while true {
            let chunk = (try handle.read(upToCount: 1 << 16)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalizeHex()
    }
}
