import Foundation
import Security

/// Trust-on-first-use certificate capture for the pairing ceremony.
///
/// The pairing handshake is the one moment this app has no pinned
/// certificate on disk yet, so `URLSession` falls back to default trust
/// evaluation (see `APIClient`'s own doc comment). This delegate observes
/// that same handshake and *records* the server's trust anchor without
/// changing the outcome of the challenge — `.performDefaultHandling` is
/// always returned, whatever is captured. Trust is not narrowed until
/// pairing actually succeeds and `writeCapturedCertificate(to:)` is called
/// deliberately, and only after the credential is durably stored (see
/// `PairingCoordinator`): a failed pairing must never leave a pin behind
/// that would break a later attempt against a re-issued certificate.
final class PinnedCertificateCapture: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedCertificateData: Data?

    /// The DER bytes of the trust anchor captured from the most recent
    /// server-trust challenge, if any. `nil` until a handshake has
    /// actually occurred.
    var capturedCertificateData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedCertificateData
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        defer { completionHandler(.performDefaultHandling, nil) }

        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust,
            let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
            let anchor = chain.last
        else {
            return
        }

        let data = SecCertificateCopyData(anchor) as Data
        lock.lock()
        _capturedCertificateData = data
        lock.unlock()
    }

    /// Writes the captured trust anchor to `url` with `0600` permissions.
    /// Returns `false` (never throws) when nothing was captured or the
    /// write failed — the caller decides what that means for the ceremony;
    /// this type only ever reports what actually landed on disk.
    @discardableResult
    func writeCapturedCertificate(to url: URL) -> Bool {
        guard let data = capturedCertificateData else { return false }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
