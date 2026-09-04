import Foundation
import CryptoKit

/// Reads a game's save artifact once, returning its raw bytes or `nil`
/// if unavailable. Injected so `SaveCapturePoller` never touches the
/// filesystem directly, which is what lets a test drive quiescence
/// deterministically with an in-memory byte sequence.
protocol SaveArtifactSource: Sendable {
    func readArtifact() -> Data?
}

/// Reads the real on-disk artifact at `url`.
struct FileSaveArtifactSource: SaveArtifactSource {
    let url: URL

    func readArtifact() -> Data? {
        try? Data(contentsOf: url)
    }
}

/// A clock a test can drive without sleeping for real seconds.
protocol SaveCaptureClock: Sendable {
    func now() -> Date
}

struct SystemSaveCaptureClock: SaveCaptureClock {
    func now() -> Date { Date() }
}

/// One promoted capture: the whole buffer's digest, size, where it was
/// written durably on disk (D-06), and when.
struct CapturedSave: Equatable {
    let sha256: String
    let sizeBytes: Int
    let localPath: String
    let capturedAt: Date
}

enum SaveCaptureError: Error, Equatable {
    case writeFailed
}

/// Reads the adapter-declared save artifact once per second while a
/// game session is open and promotes at most one revision per
/// quiescent state (D-01, D-04). Raw SRAM bytes have no header,
/// checksum, or length field, so **three consecutive identical reads**
/// are required before a capture is promoted (D-03) — temporal
/// quiescence is the only signal available, and Playstead never parses
/// save bytes, here or anywhere else.
///
/// The whole artifact is read into one buffer and hashed once with a
/// one-shot `SHA256.hash(data:)` — never `StreamingSHA256`, which is
/// reserved for a future large or multi-file artifact. On a quiescent,
/// not-yet-promoted digest, the write order is exactly D-06's: temp
/// file, fsync, rename, fsync the containing directory, and only then
/// does the caller insert the SQLite row (`SaveStore.insertRevision`,
/// called by whatever wires this poller into a play session — never by
/// this type itself, which owns bytes-on-disk durability only).
///
/// `settle()` is the unconditional post-session pass (D-05): it never
/// branches on how the session ended, because dirty `MAP_SHARED` pages
/// can land after process death and a post-exit read can genuinely see
/// bytes no pre-exit read saw.
actor SaveCapturePoller {
    private let source: SaveArtifactSource
    private let clock: SaveCaptureClock
    private let destinationDirectory: URL
    let pollInterval: TimeInterval

    /// The most recent reads' digests, most recent last, capped at 3.
    private var recentDigests: [String] = []
    private var lastPromotedDigest: String?
    private var pollTask: Task<Void, Never>?

    init(
        source: SaveArtifactSource,
        clock: SaveCaptureClock = SystemSaveCaptureClock(),
        destinationDirectory: URL,
        pollInterval: TimeInterval = 1.0,
        /// The digest of the local head already persisted for this
        /// save's line, if any. Seeds `lastPromotedDigest` so a
        /// same-device capture that is byte-identical to what's already
        /// on record creates no second local revision (D-30's client
        /// half) — the caller (whatever wires this poller to a play
        /// session) is responsible for reading that head from
        /// `SaveStore` before construction; this type stays free of any
        /// direct `SaveStore` dependency.
        knownHeadDigest: String? = nil
    ) {
        self.source = source
        self.clock = clock
        self.destinationDirectory = destinationDirectory
        self.pollInterval = pollInterval
        self.lastPromotedDigest = knownHeadDigest
    }

    /// The digest of the last promoted capture, if any — exposed for
    /// same-device byte-identical de-dup checks (D-30's client half).
    var lastPromoted: String? { lastPromotedDigest }

    /// Feeds one read into the quiescence detector. Returns a capture
    /// only on the read that *completes* three consecutive identical
    /// digests, and never again for that same digest afterward — a
    /// fourth, fifth, ... identical read produces no second capture.
    @discardableResult
    func observe(_ data: Data) throws -> CapturedSave? {
        let digest = Self.digest(of: data)

        recentDigests.append(digest)
        if recentDigests.count > 3 {
            recentDigests.removeFirst(recentDigests.count - 3)
        }

        let quiescent = recentDigests.count == 3 && Set(recentDigests).count == 1
        guard quiescent, digest != lastPromotedDigest else { return nil }

        let capture = try write(data: data, digest: digest)
        lastPromotedDigest = digest
        return capture
    }

    /// The unconditional post-session settle pass (D-05). Reads the
    /// artifact once more regardless of how the session ended and
    /// promotes a capture if its bytes differ from the last promoted
    /// digest — deliberately not gated by `recentDigests`, since a
    /// session can end the instant after a genuine byte change with no
    /// chance to accumulate three matching polls first.
    @discardableResult
    func settle() throws -> CapturedSave? {
        guard let data = source.readArtifact() else { return nil }
        let digest = Self.digest(of: data)
        guard digest != lastPromotedDigest else { return nil }

        let capture = try write(data: data, digest: digest)
        lastPromotedDigest = digest
        recentDigests = [digest, digest, digest]
        return capture
    }

    /// Starts the session-scoped 1 Hz poll loop (D-01). Stopped by
    /// `stop()` at session end, immediately followed by `settle()` by
    /// whichever caller owns the play session's lifecycle.
    func start() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let data = await self.readFromSource() {
                    _ = try? await self.observe(data)
                }
                try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func readFromSource() -> Data? {
        source.readArtifact()
    }

    private func write(data: Data, digest: String) throws -> CapturedSave {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let tempURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let finalURL = destinationDirectory.appendingPathComponent("\(digest).sav")

        do {
            try data.write(to: tempURL, options: .atomic)
            try Self.fsync(fileAt: tempURL)
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            try Self.fsync(directoryAt: destinationDirectory)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw SaveCaptureError.writeFailed
        }

        return CapturedSave(sha256: digest, sizeBytes: data.count, localPath: finalURL.path, capturedAt: clock.now())
    }

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fsync(fileAt url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw SaveCaptureError.writeFailed }
        defer { close(fd) }
        _ = Foundation.fsync(fd)
    }

    private static func fsync(directoryAt url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = Foundation.fsync(fd)
    }
}
