import Foundation
import CryptoKit

/// One file inside an artifact set: its logical path, byte size, and raw
/// content sha256. No wall-clock value participates in this type or in
/// `SaveArtifactSet`, so the same files always produce the same manifest
/// (D-08's "timestamp-free" requirement).
struct SaveArtifactEntry: Equatable, Codable {
    let path: String
    let size: Int
    let sha256: String
}

/// The capture unit (D-08): a sorted, timestamp-free `(path, size,
/// sha256)` manifest. mGBA yields exactly one entry today; the type
/// exists so a directory-shaped or multi-file save (memory cards, an
/// `.srm` plus an `.rtc`) slots in later without a schema migration.
/// This is the only abstraction in the phase built ahead of need.
///
/// **The stored blob digest is the raw artifact sha256, never
/// `manifestDigest`.** Dedupe (D-30), export filenames (D-58), and the
/// compatibility gate (D-19) all key off the raw digest a user would see
/// from `sha256sum` on the file; a manifest digest over a single entry
/// would make those three subsystems disagree with that. `manifestDigest`
/// is recorded alongside for the multi-artifact future, never used for
/// any of those three purposes.
struct SaveArtifactSet: Equatable, Codable {
    let entries: [SaveArtifactEntry]

    /// Sorts by path so two computations over the same files -- in any
    /// enumeration order -- produce byte-identical manifests.
    init(entries: [SaveArtifactEntry]) {
        self.entries = entries.sorted { $0.path < $1.path }
    }

    /// A stable digest over the sorted, timestamp-free manifest. Two
    /// artifact sets built from identical files are byte-identical here,
    /// which is what makes the manifest itself reusable as an equality
    /// check without re-reading every underlying file.
    var manifestDigest: String {
        let canonical = entries.map { "\($0.path)\0\($0.size)\0\($0.sha256)" }.joined(separator: "\n")
        return Self.hex(SHA256.hash(data: Data(canonical.utf8)))
    }

    /// Builds the artifact set for today's single-file capture (mGBA):
    /// one entry at `path` whose size and sha256 are computed from
    /// `data`. `path` is a logical identifier, not necessarily a real
    /// filesystem path -- it exists so a future multi-file artifact can
    /// populate genuine relative paths without changing this type's shape.
    static func single(data: Data, path: String) -> SaveArtifactSet {
        SaveArtifactSet(entries: [
            SaveArtifactEntry(path: path, size: data.count, sha256: hex(SHA256.hash(data: data)))
        ])
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
