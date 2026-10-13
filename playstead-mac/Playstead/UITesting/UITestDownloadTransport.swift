#if UI_TESTING
import Foundation
import CryptoKit

/// A finite, deterministic byte stream for the packaged download-progress
/// journey. The production DownloadEngine consumes these chunks and derives
/// its progress events from bytes actually received by URLSession.
enum UITestDownloadFixture {
    static let assetID = "00000000-0000-7000-8000-000000000105"
    static let bytes: Data = {
        // Two production engine chunks let the test hold after one complete
        // chunk and observe progress derived from received bytes.
        var rom = Data(repeating: 0x31, count: 131_072)
        rom[0x143] = 0xC0
        rom[0x147] = 0x1B
        rom[0x148] = 0x02
        rom[0x149] = 0x03
        rom[0x14D] = (0x134...0x14C).reduce(UInt8(0)) { sum, offset in
            sum &- rom[offset] &- 1
        }
        return rom
    }()
    static let sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

/// Test transport is accepted only for the one synthetic host and exact ROM
/// digest. It pauses after half the actual response body and has a bounded
/// release wait so teardown cannot strand a URLSession worker.
final class UITestDownloadURLProtocol: URLProtocol {
    private static let gate = DownloadTransferGate()
    private static let evidence = DownloadTransferEvidence()

    override class func canInit(with request: URLRequest) -> Bool {
        // Own every request made by this injected session so unexpected
        // URLs fail closed instead of falling through to real networking.
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              request.httpMethod == "GET",
              url.scheme == "https",
              url.host == "ui-test-download.invalid",
              url.path == "/api/v1/blobs/\(UITestDownloadFixture.sha256)",
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(UITestDownloadFixture.bytes.count)", "Content-Type": "application/octet-stream"]
              )
        else {
            Self.evidence.recordRejectedRequest()
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.evidence.recordRequest()
        let bytes = UITestDownloadFixture.bytes
        let midpoint = bytes.count / 2
        let currentGate = Self.gate.current()
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(bytes.prefix(midpoint)))
            Self.evidence.recordReceivedBytes(midpoint)
            if currentGate.wait(timeout: .now() + 120) == .success {
                self.client?.urlProtocol(self, didLoad: Data(bytes.suffix(bytes.count - midpoint)))
                Self.evidence.recordReceivedBytes(bytes.count - midpoint)
                self.client?.urlProtocolDidFinishLoading(self)
            } else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            }
        }
    }

    override func stopLoading() {
        // Cancellation/teardown releases the bounded worker without treating
        // it as a successful test-driven transfer completion.
        Self.gate.release()
    }

    static func makeSession() -> URLSession {
        gate.reset()
        evidence.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }

    static func releaseHeldTransfer() {
        gate.release()
    }

    static var evidenceValue: String { evidence.value }
}

private final class DownloadTransferGate: @unchecked Sendable {
    private let lock = NSLock()
    private var semaphore = DispatchSemaphore(value: 0)

    func current() -> DispatchSemaphore {
        lock.lock()
        defer { lock.unlock() }
        return semaphore
    }

    func reset() {
        lock.lock()
        semaphore = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func release() {
        current().signal()
    }
}

private final class DownloadTransferEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var rejectedRequests = 0
    private var receivedBytes = 0

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return "requests=\(requests);rejected=\(rejectedRequests);receivedBytes=\(receivedBytes)"
    }

    func reset() {
        lock.lock()
        requests = 0
        rejectedRequests = 0
        receivedBytes = 0
        lock.unlock()
    }

    func recordRequest() {
        lock.lock()
        requests += 1
        lock.unlock()
    }

    func recordRejectedRequest() {
        lock.lock()
        rejectedRequests += 1
        lock.unlock()
    }

    func recordReceivedBytes(_ count: Int) {
        lock.lock()
        receivedBytes += count
        lock.unlock()
    }
}
#endif
