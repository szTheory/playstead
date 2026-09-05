#if UI_TESTING
import Foundation

/// Records every HTTP(S) request attempted anywhere in this process --
/// registered globally via `URLProtocol.registerClass`, so it intercepts
/// `URLSession.shared` and any session configuration that does not
/// explicitly override `protocolClasses`, not merely the app's own
/// `APIClient` session. Plan 04-13's zero-network Play flow assertion is
/// deliberately stricter than the shipped blob-only precedent: it must
/// fail if a single request is recorded, including one issued from a
/// detached or fire-and-forget task -- a post-spawn fetch could not help
/// anyway, because mutating a mmap'd `.sav` under a running emulator is
/// itself corruption.
final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [String] = []
    private static var armed = false

    static func armRecording() {
        lock.lock()
        recorded = []
        armed = true
        lock.unlock()
        URLProtocol.registerClass(RecordingURLProtocol.self)
    }

    static func disarmRecording() {
        lock.lock()
        armed = false
        lock.unlock()
        URLProtocol.unregisterClass(RecordingURLProtocol.self)
    }

    static var recordedRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard armed, let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        RecordingURLProtocol.lock.lock()
        RecordingURLProtocol.recorded.append(request.url?.absoluteString ?? "unknown")
        RecordingURLProtocol.lock.unlock()
        let error = NSError(
            domain: "PlaysteadZeroNetworkPlayFlowProof", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "network access is forbidden during the zero-network Play flow proof"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
#endif
