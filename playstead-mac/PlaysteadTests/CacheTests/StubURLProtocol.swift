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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        DispatchQueue.global().async { [client, stub] in
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
        return URLSession(configuration: config)
    }

    static func reset() {
        responder = nil
        requestLog = []
    }
}
