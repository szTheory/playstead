import Foundation

/// A scriptable `URLProtocol` stub so `DownloadEngine` tests exercise
/// 206/416/200-on-resume server behavior — and simulated mid-stream
/// transport failures — without a live HTTP server.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        /// The body delivered as one or more `didLoad` chunks, so tests
        /// can simulate a stream that is interrupted partway through.
        let bodyChunks: [Data]
        /// When true, after delivering `bodyChunks` the load fails with
        /// a transport error instead of finishing normally — simulating
        /// a connection drop mid-transfer.
        let failAfter: Bool

        init(statusCode: Int, headers: [String: String], bodyChunks: [Data], failAfter: Bool) {
            self.statusCode = statusCode
            self.headers = headers
            self.bodyChunks = bodyChunks
            self.failAfter = failAfter
        }

        /// Convenience for the common single-chunk, non-interrupted case.
        init(statusCode: Int, headers: [String: String], body: Data) {
            self.init(statusCode: statusCode, headers: headers, bodyChunks: [body], failAfter: false)
        }
    }

    /// One responder invoked per request; a test can inspect an
    /// internal counter to script a sequence of responses across
    /// multiple attempts made by one `DownloadEngine.download` call.
    nonisolated(unsafe) static var responder: ((URLRequest) -> Stub)?
    nonisolated(unsafe) static var requestLog: [URLRequest] = []
    /// Tracks the async response-delivery block below so `reset()` can
    /// wait for any request still in flight from the *previous* test
    /// before clearing `responder`/`requestLog` for the next one
    /// (P4-WR-004) — without this, a delayed completion callback firing
    /// after the next test has already reconfigured these statics could
    /// append into the wrong test's `requestLog` or invoke a callback
    /// against an already-torn-down `URLSessionTask`.
    private static let inFlightGroup = DispatchGroup()

    /// Header stamped into every session `makeSession()` hands out, so a
    /// request can be traced back to the session that issued it.
    private static let sessionHeader = "X-Playstead-Stub-Session"
    private static let sessionCounter = SessionCounter()
    /// Sessions whose requests may still touch `responder`/`requestLog`.
    ///
    /// WINDOWS #70: `requestLog` is process-global, and `reset()`'s
    /// `inFlightGroup.wait()` only covers a response already being
    /// DELIVERED -- it does not cover a `URLSessionTask` from an earlier
    /// test that has not yet issued its request. Such a task appends into
    /// the NEXT test's log, and `RelaunchTests`' "zero network requests"
    /// assertion then fails for a request it never made.
    ///
    /// Two buckets rather than one, because `reset()` is also called
    /// MID-test -- `SaveConflictResolverTests` calls `makeSession()` and
    /// then `reset()` inside `setUp`, and `FilterTests` resets partway
    /// through a test. Retiring every live session on `reset()` would
    /// break exactly those, which is why #70 warns against it. Instead a
    /// session must survive one full `reset()` before it is retired: by
    /// then its own test has ended, and anything it still emits is by
    /// definition stale.
    private static let liveSessions = LiveSessions()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Dropped before it can touch either static. Deliberately
        // fail-CLOSED: a request with no session stamp, or one from a
        // retired session, is precisely the cross-test leak #70 records,
        // and letting it through "just in case" is what made that leak
        // invisible for three runs.
        guard let stamp = request.value(forHTTPHeaderField: Self.sessionHeader),
              Self.liveSessions.contains(stamp)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        Self.requestLog.append(request)
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = responder(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // Deliver off the calling queue with small pauses between chunks:
        // `URLSession.bytes(for:)`'s AsyncBytes consumer needs scheduling
        // opportunities to actually drain each `didLoad` chunk before a
        // subsequent `didFailWithError`/`didFinishLoading` — delivering
        // everything synchronously in one call risks the terminal event
        // superseding buffered-but-unconsumed data.
        Self.inFlightGroup.enter()
        DispatchQueue.global().async { [client, stub] in
            defer { Self.inFlightGroup.leave() }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in stub.bodyChunks {
                Thread.sleep(forTimeInterval: 0.02)
                client?.urlProtocol(self, didLoad: chunk)
            }
            Thread.sleep(forTimeInterval: 0.02)
            if stub.failAfter {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let stamp = sessionCounter.next()
        liveSessions.open(stamp)
        config.httpAdditionalHeaders = [sessionHeader: stamp]
        return URLSession(configuration: config)
    }

    /// Called from `setUp`/`tearDown`. Waits for any response delivery
    /// still in flight from a request made before this call (e.g. the
    /// previous test) to finish before clearing `responder`/`requestLog`
    /// (P4-WR-004) — bounded so a genuinely stuck delivery (should never
    /// happen; every path above always reaches `leave()`) cannot hang
    /// the whole test run.
    static func reset() {
        _ = inFlightGroup.wait(timeout: .now() + 2)
        liveSessions.rotate()
        responder = nil
        requestLog = []
    }
}

/// Hands out a distinct stamp per session. Separate from `LiveSessions`
/// so the counter never has to be read under that lock.
private final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return String(value)
    }
}

/// The two-bucket session ledger described on `liveSessions`.
///
/// `current` holds sessions opened since the last `rotate()`; `previous`
/// holds those that have already survived one. A `rotate()` retires
/// `previous` and promotes `current`, so the newest session always lives
/// through at least one `reset()` — which is what keeps a mid-test
/// `reset()` from cancelling the session its own test is using.
private final class LiveSessions: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Set<String> = []
    private var previous: Set<String> = []

    func open(_ stamp: String) {
        lock.lock()
        defer { lock.unlock() }
        current.insert(stamp)
    }

    func contains(_ stamp: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return current.contains(stamp) || previous.contains(stamp)
    }

    func rotate() {
        lock.lock()
        defer { lock.unlock() }
        previous = current
        current = []
    }
}
