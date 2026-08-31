import Foundation

enum DownloadError: Error, Equatable {
    case invalidResponse
    case digestMismatch(expected: String, actual: String)
    case transport(String)
}

/// The pure decision this download engine makes every time a resumed
/// request's response comes back, kept as a standalone testable type
/// per the plan's own naming: whether to append onto the existing
/// partial or discard it and restart from zero.
///
/// A `206` whose `Content-Range` first byte matches the partial's
/// current length is the only case that appends. Anything else after a
/// `Range` header was sent — a `200` (server ignored/couldn't honor
/// Range), a `416` (the client's notion of size was wrong), a `206`
/// whose first byte doesn't match, or a malformed `Content-Range` —
/// restarts: appending a full body onto an existing prefix produces a
/// longer, corrupt file (D-18's footgun).
enum RangeResumeDecision: Equatable {
    case appendFrom(Int)
    case restartFromZero

    static func decide(
        sentRangeHeader: Bool,
        statusCode: Int,
        contentRangeFirstByte: Int?,
        existingLength: Int
    ) -> RangeResumeDecision {
        guard sentRangeHeader else {
            return .restartFromZero
        }
        guard statusCode == 206, let first = contentRangeFirstByte, first == existingLength else {
            return .restartFromZero
        }
        return .appendFrom(existingLength)
    }
}

/// A Swift `actor` running exactly one transfer at a time over the
/// in-process `URLSession.bytes(for:)` API (D-18). Never a background
/// `URLSession`: background resume machinery ignores custom `Range`
/// request headers, its resume data is opaque, and the system may purge
/// its temporary files — none of which is acceptable when resume
/// correctness is the requirement.
actor DownloadEngine {
    private let session: URLSession
    private let paths: AppPaths
    private let cas: CASManager
    private let chunkSize: Int
    /// Injectable for tests only — production always sleeps for real.
    private let sleeper: (@Sendable (Double) async -> Void)
    /// Test-only bound on transport-failure retries. `nil` (the
    /// production default) means unbounded, per D-18: a queued-while-
    /// offline transfer is a normal state, not an error.
    private let maxTransportAttempts: Int?

    private enum AttemptOutcome: Equatable {
        case committed
        /// The response could not be used as-is (a 416, or a 206 whose
        /// `Content-Range` doesn't match the partial's length): the
        /// partial was already truncated to zero, and the caller should
        /// immediately retry — with no `Range` header this time, since
        /// the partial is now empty — with no backoff, since this isn't
        /// a transport failure.
        case restartRequested
    }

    init(
        session: URLSession,
        paths: AppPaths,
        cas: CASManager,
        chunkSize: Int = 1 << 16,
        maxTransportAttempts: Int? = nil,
        sleeper: @escaping (@Sendable (Double) async -> Void) = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.session = session
        self.paths = paths
        self.cas = cas
        self.chunkSize = chunkSize
        self.maxTransportAttempts = maxTransportAttempts
        self.sleeper = sleeper
    }

    /// Downloads `sha256` from `url`, resuming an existing partial if
    /// one is present, retrying transport failures with unbounded
    /// exponential backoff (a queued-while-offline transfer is a normal
    /// state, not an error). Returns normally once the object is
    /// committed into the CAS (including immediately, if it was already
    /// cached). Throws `DownloadError.digestMismatch` if the completed
    /// stream's hash doesn't match — that is a genuine, non-retried
    /// failure; the caller decides whether to re-enqueue.
    func download(sha256: String, from url: URL, headers: [String: String] = [:]) async throws {
        if cas.contains(sha256) { return }

        var transportAttempt = 0
        while true {
            do {
                let outcome = try await attemptDownload(sha256: sha256, url: url, headers: headers)
                if outcome == .committed { return }
                continue // .restartRequested — immediate retry, no backoff
            } catch let error as URLError {
                transportAttempt += 1
                if let maxTransportAttempts, transportAttempt >= maxTransportAttempts {
                    throw error
                }
                await sleeper(backoffSeconds(attempt: transportAttempt))
                continue
            }
        }
    }

    private func attemptDownload(sha256: String, url: URL, headers: [String: String]) async throws -> AttemptOutcome {
        let partialURL = paths.partialURL(for: sha256)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.partials, withIntermediateDirectories: true)

        let existingLength = currentLength(of: partialURL)
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let sentRange = existingLength > 0
        if sentRange {
            request.setValue("bytes=\(existingLength)-", forHTTPHeaderField: "Range")
            request.setValue("\"\(sha256)\"", forHTTPHeaderField: "If-Range")
        }

        let bytesStream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytesStream, response) = try await session.bytes(for: request)
        } catch let error as URLError {
            throw error
        } catch {
            throw DownloadError.transport("\(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }

        let decision = RangeResumeDecision.decide(
            sentRangeHeader: sentRange,
            statusCode: http.statusCode,
            contentRangeFirstByte: firstByte(fromContentRange: http.value(forHTTPHeaderField: "Content-Range")),
            existingLength: existingLength
        )

        switch (sentRange, decision) {
        case (true, .restartFromZero) where http.statusCode != 200:
            // 416, or a malformed/mismatched 206 — this response's body
            // is not useful payload. Truncate and let the caller retry
            // immediately with a fresh (no-Range) request.
            try truncatePartial(at: partialURL, fm: fm)
            _ = try? await drain(bytesStream)
            return .restartRequested

        default:
            break
        }

        // Every remaining case has a body worth consuming: a fresh
        // (false, .restartFromZero) request, a (true, .restartFromZero)
        // 200 that ignored Range, or a (true, .appendFrom) 206.
        if decision == .restartFromZero {
            try truncatePartial(at: partialURL, fm: fm)
        } else if !fm.fileExists(atPath: partialURL.path) {
            fm.createFile(atPath: partialURL.path, contents: nil)
        }

        if !sentRange && http.statusCode != 200 {
            throw DownloadError.invalidResponse
        }

        var hasher: StreamingSHA256
        if case .appendFrom = decision {
            hasher = try StreamingSHA256.resume(from: partialURL)
        } else {
            hasher = StreamingSHA256()
        }

        let handle = try FileHandle(forWritingTo: partialURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()

        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        do {
            for try await byte in bytesStream {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    handle.write(buffer)
                    hasher.update(data: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch let error as URLError {
            if !buffer.isEmpty {
                handle.write(buffer)
                hasher.update(data: buffer)
            }
            throw error
        }
        if !buffer.isEmpty {
            handle.write(buffer)
            hasher.update(data: buffer)
        }
        try handle.close()

        let digest = hasher.finalizeHex()
        if digest == sha256 {
            try cas.commit(partialAt: partialURL, sha256: sha256)
            return .committed
        } else {
            try cas.quarantine(partialAt: partialURL, reason: "digest_mismatch expected=\(sha256) actual=\(digest)")
            throw DownloadError.digestMismatch(expected: sha256, actual: digest)
        }
    }

    private func truncatePartial(at url: URL, fm: FileManager) throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        fm.createFile(atPath: url.path, contents: nil)
    }

    /// Consumes and discards an unusable response body (e.g. a 416's
    /// error page) so the underlying connection is cleanly released.
    private func drain(_ bytesStream: URLSession.AsyncBytes) async throws {
        for try await _ in bytesStream {}
    }

    private func currentLength(of url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int) ?? 0
    }

    private func firstByte(fromContentRange header: String?) -> Int? {
        // "bytes 100-199/2000"
        guard let header, header.hasPrefix("bytes ") else { return nil }
        let rest = header.dropFirst("bytes ".count)
        guard let dashIndex = rest.firstIndex(of: "-") else { return nil }
        return Int(rest[rest.startIndex..<dashIndex])
    }

    private func backoffSeconds(attempt: Int) -> Double {
        min(pow(2.0, Double(attempt)), 60.0)
    }
}
