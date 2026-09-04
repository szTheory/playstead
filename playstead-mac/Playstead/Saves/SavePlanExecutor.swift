import Foundation
import CryptoKit

enum SavePlanExecutorError: Error, Equatable {
    /// D-21: a failed pre-restore capture aborts the whole restore, and
    /// the on-disk bytes are left exactly as they were.
    case preRestoreCaptureFailed
    /// The bytes handed back for `digest` do not hash to it — quarantined,
    /// never written, never deleted (D-23).
    case digestMismatch(expected: String, actual: String)
    case stagingWriteFailed
    case renameFailed
}

/// The two impure capabilities `SavePlanExecutor` needs and does not own
/// itself: reading a revision's bytes back from wherever they are
/// stored locally, capturing whatever currently sits at the restore
/// target before it is overwritten, and quarantining bytes that fail
/// their own digest check. Injected so this type has zero direct
/// dependency on `CASManager`/`SaveStore`/`SaveCapturePoller` — a test
/// double proves every behaviour without a real CAS on disk.
protocol SavePlanExecutorEnvironment {
    /// Returns the exact bytes recorded for `digest`. Never issues a
    /// network request — the caller (D-43's prefetch) is responsible for
    /// the bytes already being local before a `.restore`/`.fastForward`
    /// plan ever reaches this type.
    func revisionBytes(forDigest digest: String) throws -> Data

    /// Captures whatever currently exists at `targetURL` as its own
    /// revision, before it is about to be overwritten (D-21). A no-op —
    /// never a thrown error — when nothing exists at `targetURL` yet.
    func captureExistingFile(at targetURL: URL) throws

    /// Called when the bytes returned for `digest` fail their own
    /// digest check — quarantines them (moves them aside, never
    /// deletes) and offers a redownload remedy. This type's own
    /// responsibility ends at refusing to write corrupt bytes; where
    /// they are physically quarantined is the environment's concern.
    func quarantineCorruptRevision(digest: String, actualDigest: String)
}

/// The impure counterpart to `LaunchSavePlanner`: executes exactly one
/// `SavePlan` against one target `.sav` path. `.fresh` and `.keep`
/// perform **literally nothing** — not even a stat beyond what the
/// planner already read, matching D-44's invariant that everything but
/// a provable restore/fast-forward is `.keep`.
///
/// Write order for `.restore`/`.fastForward` (D-47): stage a temp file
/// in the *same* directory as the target (so the final rename is a
/// same-volume, atomic operation), `fsync` it, `rename` it onto the
/// target, then `fsync` the containing directory. The target is never
/// opened for writing in place — a torn in-place write yields a `.sav`
/// that is neither the old nor the new save, and the emulator will mmap
/// it as truth. A crash between the staged write and the rename leaves
/// the prior `.sav` completely untouched, because the rename is the
/// only step that ever touches the target path.
struct SavePlanExecutor {
    let environment: SavePlanExecutorEnvironment

    /// Executes `plan` against `targetURL` — the resolved
    /// `saves/<assetSetID>/<romBaseName>.sav` path, derived by the
    /// caller from `PlaysteadApp.saveDirectoryURL(forAssetSetID:)`. This
    /// type never constructs that path itself and never reads
    /// `AppPaths.launch`; the caller is responsible for resolving a path
    /// that is always a sibling of `launch/`, never inside it.
    func execute(_ plan: SavePlan, targetURL: URL) throws {
        switch plan {
        case .fresh, .keep:
            return
        case .restore(let digest, _), .fastForward(let digest):
            try restoreOrFastForward(digest: digest, targetURL: targetURL)
        }
    }

    private func restoreOrFastForward(digest: String, targetURL: URL) throws {
        do {
            try environment.captureExistingFile(at: targetURL)
        } catch {
            throw SavePlanExecutorError.preRestoreCaptureFailed
        }

        let bytes = try environment.revisionBytes(forDigest: digest)

        // Always a full re-hash -- deliberately never the size+inode+
        // mtime shortcut a hundred-megabyte ROM preflight uses. At
        // ≤128 KB this costs well under a millisecond and buys a
        // strictly stronger guarantee (D-23).
        let actualDigest = Self.hex(of: bytes)
        guard actualDigest == digest else {
            environment.quarantineCorruptRevision(digest: digest, actualDigest: actualDigest)
            throw SavePlanExecutorError.digestMismatch(expected: digest, actual: actualDigest)
        }

        let directory = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stagingURL = directory.appendingPathComponent(".staging-\(UUID().uuidString).sav")

        try Self.writeStagedFileDurably(bytes: bytes, to: stagingURL)
        do {
            try Self.renameIntoPlaceDurably(from: stagingURL, to: targetURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    // MARK: - Durable write primitives (D-47)

    private static func writeStagedFileDurably(bytes: Data, to stagingURL: URL) throws {
        let fd = open(stagingURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw SavePlanExecutorError.stagingWriteFailed }

        var writeSucceeded = true
        bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, base.advanced(by: offset), buffer.count - offset)
                if n <= 0 {
                    writeSucceeded = false
                    break
                }
                offset += n
            }
        }

        // fsync the FILE before rename -- durability of the bytes
        // themselves, independent of the directory-entry fsync below.
        if writeSucceeded, fsync(fd) != 0 {
            writeSucceeded = false
        }
        close(fd)

        guard writeSucceeded else { throw SavePlanExecutorError.stagingWriteFailed }
    }

    private static func renameIntoPlaceDurably(from stagingURL: URL, to targetURL: URL) throws {
        guard rename(stagingURL.path, targetURL.path) == 0 else {
            throw SavePlanExecutorError.renameFailed
        }
        // fsync the DIRECTORY -- durability of the rename's directory
        // entry itself, the second of D-47's two required fsyncs.
        let dirFD = open(targetURL.deletingLastPathComponent().path, O_RDONLY)
        guard dirFD >= 0 else { return }
        fsync(dirFD)
        close(dirFD)
    }

    private static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
