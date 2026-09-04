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

/// D-04's three capture tiers. `staged` is the durable rolling capture
/// written during an open session -- each one supersedes the last, and
/// none of them is itself a promoted revision. `promoted` is the exactly-
/// one-per-session revision created at session end. `baseline` is the
/// session-start revision created only when the on-disk artifact changed
/// outside a Playstead session.
enum SaveCaptureTier: String, Equatable {
    case staged
    case promoted
    case baseline
}

/// Whether a capture's bytes were produced inside a live Playstead
/// session (`session`) or discovered already different on disk at
/// session start (`external`, D-04's baseline case).
enum SaveCaptureOrigin: String, Equatable {
    case session
    case external
}

/// One capture: the whole buffer's digest, size, where it was written
/// durably on disk (D-06), when, which tier it belongs to, and the
/// artifact-set manifest it was computed from (D-08). `sha256` is always
/// the raw artifact digest -- the stored blob identity -- never the
/// manifest digest; `artifactSet.manifestDigest` is recorded alongside it,
/// not used in its place.
struct CapturedSave: Equatable {
    let sha256: String
    let sizeBytes: Int
    let localPath: String
    let capturedAt: Date
    let tier: SaveCaptureTier
    let origin: SaveCaptureOrigin
    let artifactSet: SaveArtifactSet
    let sessionID: String
}

enum SaveCaptureError: Error, Equatable {
    case writeFailed
}

/// Reads the adapter-declared save artifact once per second while a
/// game session is open and, per D-04, keeps at most one durable rolling
/// **staged** capture per session -- each superseding the last -- and
/// promotes **exactly one revision per session**, at session end. Raw
/// SRAM bytes have no header, checksum, or length field, so **three
/// consecutive identical reads** are required before a staged capture is
/// written (D-03) -- temporal quiescence is the only signal available,
/// and Playstead never parses save bytes, here or anywhere else.
///
/// The whole artifact is read into one buffer and hashed once with a
/// one-shot `SHA256.hash(data:)` -- never `StreamingSHA256`, which is
/// reserved for a future large or multi-file artifact. Every durable
/// write follows D-06's exact order: temp file, `fsync`, `rename`,
/// `fsync` the containing directory, and only then does the caller
/// insert the SQLite row (`SaveStore.insertRevision`, called by whatever
/// wires this poller into a play session -- never by this type itself,
/// which owns bytes-on-disk durability only).
///
/// A **staged** capture is written to one fixed, session-scoped path,
/// atomically overwritten on every supersession -- it is a rolling
/// working copy, not a permanent artifact. A **promoted** or **baseline**
/// capture is written to a permanent, content-addressed `<digest>.sav`
/// path, exactly as a promoted revision was written before this plan.
///
/// `settle()` is the unconditional post-session pass (D-05): it never
/// branches on how the session ended, because dirty `MAP_SHARED` pages
/// can land after process death and a post-exit read can genuinely see
/// bytes no pre-exit read saw. `promote()` is the distinct D-04 step that
/// turns whatever the session's newest staged bytes are (from `observe()`
/// or from `settle()`) into the one permanent promoted revision; a
/// session with no byte changes at all promotes nothing.
actor SaveCapturePoller {
    private let source: SaveArtifactSource
    private let clock: SaveCaptureClock
    private let destinationDirectory: URL
    private let artifactRelativePath: String
    let pollInterval: TimeInterval
    let sessionID: String

    /// The most recent reads' digests, most recent last, capped at 3.
    private var recentDigests: [String] = []
    /// The digest already durably recorded as this line's head -- seeded
    /// at construction from whatever `SaveStore` already has (D-30's
    /// client half), and advanced by `startSession()`'s baseline and by
    /// `promote()`. Never advanced by an ordinary staged capture.
    private var lastPromotedDigest: String?
    /// The digest of the most recent staged capture written THIS
    /// session -- prevents repeatedly re-writing identical bytes on
    /// every 1 Hz poll once a session's content has already settled.
    private var lastStagedDigest: String?
    /// The session's newest staged capture, if any -- what `promote()`
    /// turns into the session's one permanent promoted revision.
    private var latestStaged: CapturedSave?
    private var pollTask: Task<Void, Never>?

    init(
        source: SaveArtifactSource,
        clock: SaveCaptureClock = SystemSaveCaptureClock(),
        destinationDirectory: URL,
        pollInterval: TimeInterval = 1.0,
        /// A logical identifier for the single artifact this poller
        /// captures -- the one entry in its `SaveArtifactSet` manifest
        /// (D-08). Not necessarily a real filesystem path; a future
        /// multi-file artifact would populate genuine relative paths
        /// instead of using this single-entry constructor at all.
        artifactRelativePath: String = "save",
        sessionID: String = UUID().uuidString,
        /// The digest of the local head already persisted for this
        /// save's line, if any. Seeds `lastPromotedDigest` so a
        /// same-device capture that is byte-identical to what's already
        /// on record creates no local revision (D-30's client half) and
        /// so `startSession()` can detect an out-of-band change (D-04's
        /// baseline case) -- the caller (whatever wires this poller to a
        /// play session) is responsible for reading that head from
        /// `SaveStore` before construction; this type stays free of any
        /// direct `SaveStore` dependency.
        knownHeadDigest: String? = nil
    ) {
        self.source = source
        self.clock = clock
        self.destinationDirectory = destinationDirectory
        self.artifactRelativePath = artifactRelativePath
        self.pollInterval = pollInterval
        self.sessionID = sessionID
        self.lastPromotedDigest = knownHeadDigest
    }

    /// The digest of the last promoted capture, if any -- exposed for
    /// same-device byte-identical de-dup checks (D-30's client half).
    var lastPromoted: String? { lastPromotedDigest }

    /// D-04's session-start baseline check. Call once, before any
    /// `observe()` polling begins. Reads the artifact's current on-disk
    /// bytes and compares them to the already-known head: when they
    /// differ, writes and returns a durable `baseline` capture marked
    /// `origin: external`, and that digest becomes the new known head
    /// for the rest of this session. When they match -- or there is no
    /// known head yet (a brand new line has nothing to diverge from) --
    /// returns `nil` and creates nothing.
    @discardableResult
    func startSession() throws -> CapturedSave? {
        guard let head = lastPromotedDigest else { return nil }
        guard let data = source.readArtifact(), !data.isEmpty else { return nil }
        let digest = Self.digest(of: data)
        guard digest != head else { return nil }

        let artifactSet = SaveArtifactSet.single(data: data, path: artifactRelativePath)
        let capture = try write(
            data: data, digest: digest, tier: .baseline, origin: .external, artifactSet: artifactSet, fixedFilename: nil
        )
        lastPromotedDigest = digest
        return capture
    }

    /// Feeds one read into the quiescence detector. Writes a **staged**
    /// capture only on the read that *completes* three consecutive
    /// identical digests, and never again for that same digest afterward
    /// -- a fourth, fifth, ... identical read produces no second staged
    /// capture. Bytes identical to the already-known head (from a prior
    /// session, or from this session's own baseline) are never staged at
    /// all -- there is nothing new to capture.
    @discardableResult
    func observe(_ data: Data) throws -> CapturedSave? {
        guard !data.isEmpty else { return nil }
        let digest = Self.digest(of: data)

        recentDigests.append(digest)
        if recentDigests.count > 3 {
            recentDigests.removeFirst(recentDigests.count - 3)
        }

        let quiescent = recentDigests.count == 3 && Set(recentDigests).count == 1
        guard quiescent, digest != lastPromotedDigest, digest != lastStagedDigest else { return nil }

        let artifactSet = SaveArtifactSet.single(data: data, path: artifactRelativePath)
        let capture = try write(
            data: data, digest: digest, tier: .staged, origin: .session, artifactSet: artifactSet,
            fixedFilename: stagedFilename
        )
        lastStagedDigest = digest
        latestStaged = capture
        return capture
    }

    /// The unconditional post-session settle pass (D-05). Reads the
    /// artifact once more regardless of how the session ended and writes
    /// a **staged** capture if its bytes differ from both the known head
    /// and the most recently staged digest -- deliberately not gated by
    /// `recentDigests`, since a session can end the instant after a
    /// genuine byte change with no chance to accumulate three matching
    /// polls first.
    @discardableResult
    func settle() throws -> CapturedSave? {
        guard let data = source.readArtifact(), !data.isEmpty else { return nil }
        let digest = Self.digest(of: data)
        guard digest != lastPromotedDigest, digest != lastStagedDigest else { return nil }

        let artifactSet = SaveArtifactSet.single(data: data, path: artifactRelativePath)
        let capture = try write(
            data: data, digest: digest, tier: .staged, origin: .session, artifactSet: artifactSet,
            fixedFilename: stagedFilename
        )
        lastStagedDigest = digest
        latestStaged = capture
        recentDigests = [digest, digest, digest]
        return capture
    }

    /// D-04's session-end promotion. Takes the session's newest staged
    /// bytes -- whichever is newest, from `observe()` during play or
    /// from `settle()`'s unconditional read -- and durably re-materializes
    /// them at their permanent, content-addressed location as the one
    /// **promoted** revision for this session. A session that never
    /// staged anything (its bytes never differed from the already-known
    /// head) promotes nothing.
    @discardableResult
    func promote() throws -> CapturedSave? {
        guard let staged = latestStaged else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: staged.localPath)) else { return nil }

        let capture = try write(
            data: data, digest: staged.sha256, tier: .promoted, origin: staged.origin, artifactSet: staged.artifactSet,
            fixedFilename: nil
        )
        lastPromotedDigest = staged.sha256
        latestStaged = nil
        lastStagedDigest = nil
        return capture
    }

    /// Starts the session-scoped 1 Hz poll loop (D-01). Stopped by
    /// `stop()` at session end, immediately followed by `settle()` and
    /// `promote()` by whichever caller owns the play session's lifecycle.
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

    private var stagedFilename: String {
        "session-\(sessionID).staged.sav"
    }

    /// Writes `data` durably at `destinationDirectory`, following D-06's
    /// exact order: one buffer already in hand, one digest already
    /// computed, temp file, `fsync`, `rename`, `fsync` the containing
    /// directory. `fixedFilename`, when given, names a rolling path a
    /// staged capture overwrites on every supersession; `nil` names a
    /// permanent, content-addressed `<digest>.sav` path (promoted and
    /// baseline captures).
    private func write(
        data: Data, digest: String, tier: SaveCaptureTier, origin: SaveCaptureOrigin, artifactSet: SaveArtifactSet,
        fixedFilename: String?
    ) throws -> CapturedSave {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let tempURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let finalURL = destinationDirectory.appendingPathComponent(fixedFilename ?? "\(digest).sav")

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

        return CapturedSave(
            sha256: digest, sizeBytes: data.count, localPath: finalURL.path, capturedAt: clock.now(),
            tier: tier, origin: origin, artifactSet: artifactSet, sessionID: sessionID
        )
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
