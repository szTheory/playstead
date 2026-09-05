import Foundation
import CryptoKit

/// The production `SavePlanExecutorEnvironment`, backed by the real
/// on-disk CAS. Before this plan (WINDOWS #37) the only conformances
/// were a test double (`SavePlanExecutorTests.FakeSavePlanExecutorEnvironment`)
/// and `UITestBootstrap`'s `KnownDigestEnvironment` harness — this is
/// what makes `SavePlanExecutor` reachable from a real Play launch.
struct LaunchSaveEnvironment: SavePlanExecutorEnvironment {
    let casManager: CASManager

    /// Returns the exact bytes committed under `digest`. Never issues a
    /// network request: a digest absent from the CAS throws immediately
    /// (D-43/D-F03) rather than reaching for the bytes over the wire —
    /// the launch path is forbidden from fetching bytes it does not
    /// already hold locally.
    func revisionBytes(forDigest digest: String) throws -> Data {
        guard casManager.contains(digest) else {
            throw SavePlanExecutorError.digestMismatch(expected: digest, actual: "absent-from-cas")
        }
        let url = try casManager.objectURL(for: digest)
        return try Data(contentsOf: url)
    }

    /// Preserves whatever currently sits at `targetURL` before it is
    /// overwritten (D-21), by committing it into the CAS under its own
    /// content digest — the same custody boundary every other cache
    /// object already goes through, so this Mac never loses the only
    /// copy of a save it hadn't recorded yet. A missing or empty file is
    /// a no-op: there is nothing to preserve. Recording this as a full
    /// `SaveStore` revision row (visible in `SaveHistorySheet`) is a
    /// wider change than this plan's declared files reach — see the
    /// SUMMARY's "Known Stubs" — this method's own contract is only that
    /// the bytes are never lost, which committing them into the CAS
    /// already guarantees.
    func captureExistingFile(at targetURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetURL.path) else { return }
        let bytes = try Data(contentsOf: targetURL)
        guard !bytes.isEmpty else { return }

        let digest = Self.hex(of: bytes)
        guard !casManager.contains(digest) else { return }

        let partialURL = try casManager.paths.partialURL(for: digest)
        try fm.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: partialURL, options: .atomic)
        try casManager.commit(partialAt: partialURL, sha256: digest)
    }

    /// Routes to the CAS's own quarantine path — moves the corrupt
    /// object aside and writes a reason file, never deletes it (D-23).
    func quarantineCorruptRevision(digest: String, actualDigest: String) {
        guard let url = try? casManager.objectURL(for: digest) else { return }
        try? casManager.quarantine(
            partialAt: url, reason: "digest mismatch: expected \(digest), actual \(actualDigest)"
        )
    }

    private static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
