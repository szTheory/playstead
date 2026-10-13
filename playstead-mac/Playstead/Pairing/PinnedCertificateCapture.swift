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
    /// URLSession reports an intentional delegate cancellation as -999. Keep
    /// only this safe provenance bit so the pairing boundary can distinguish
    /// a rejected supplied anchor from an ordinary transport cancellation.
    private var didRejectSuppliedTrustAnchor = false
    /// A recovery-only, caller-supplied trust anchor. Production leaves this
    /// nil and therefore retains its trust-on-first-use default handling.
    private let suppliedTrustAnchorData: Data?

    /// Seams a test uses to stand in for a real TLS handshake. The default
    /// argument (`nil`) keeps every production call site
    /// (`PinnedCertificateCapture()` in `PlaysteadApp.makePairingCoordinator()`)
    /// unchanged — production always constructs with nothing pre-seeded and
    /// relies on `urlSession(_:didReceive:)` to populate it from a real
    /// challenge.
    init(capturedCertificateData: Data? = nil, suppliedTrustAnchorData: Data? = nil) {
        self._capturedCertificateData = capturedCertificateData
        self.suppliedTrustAnchorData = suppliedTrustAnchorData
        super.init()
    }

    /// Converts a recovery-certificate file selected by the owner into DER
    /// only when it is a single, parseable X.509 certificate. The recovery
    /// handoff commonly provides PEM, whereas Security's certificate API
    /// accepts DER. This deliberately does not accept a bundle or silently
    /// fall back to default trust.
    static func certificateData(fromRecoveryFile data: Data) -> Data? {
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return data
        }

        guard let text = String(data: data, encoding: .utf8),
              let begin = text.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = text.range(of: "-----END CERTIFICATE-----", range: begin.upperBound..<text.endIndex)
        else { return nil }

        let body = text[begin.upperBound..<end.lowerBound]
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let decoded = Data(base64Encoded: body),
              SecCertificateCreateWithData(nil, decoded as CFData) != nil
        else { return nil }
        return decoded
    }

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
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let serverTrust = challenge.protectionSpace.serverTrust
        switch disposition(for: serverTrust) {
        case .useCredential:
            captureAnchor(from: serverTrust)
            completionHandler(.useCredential, serverTrust.map(URLCredential.init(trust:)))
        case .performDefaultHandling:
            captureAnchor(from: serverTrust)
            completionHandler(.performDefaultHandling, nil)
        default:
            recordSuppliedTrustAnchorRejection()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Uses the supplied anchor as the *only* trust root when one exists.
    /// An absent anchor deliberately retains platform-default evaluation;
    /// malformed or mismatched supplied bytes fail closed rather than falling
    /// back to system trust.
    func disposition(for serverTrust: SecTrust?) -> URLSession.AuthChallengeDisposition {
        guard let suppliedTrustAnchorData else { return .performDefaultHandling }
        guard
            let serverTrust,
            let anchor = SecCertificateCreateWithData(nil, suppliedTrustAnchorData as CFData)
        else {
            return .cancelAuthenticationChallenge
        }

        SecTrustSetAnchorCertificates(serverTrust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        return SecTrustEvaluateWithError(serverTrust, &error)
            ? .useCredential
            : .cancelAuthenticationChallenge
    }

    /// Returns and clears the preceding recovery-anchor rejection without
    /// exposing certificate, server, request, or user data.
    func consumeSuppliedTrustAnchorRejection() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let rejected = didRejectSuppliedTrustAnchor
        didRejectSuppliedTrustAnchor = false
        return rejected
    }

    private func recordSuppliedTrustAnchorRejection() {
        guard suppliedTrustAnchorData != nil else { return }
        lock.lock()
        didRejectSuppliedTrustAnchor = true
        lock.unlock()
    }

    private func captureAnchor(from serverTrust: SecTrust?) {
        guard
            let serverTrust,
            let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
            let anchor = chain.last
        else { return }
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
