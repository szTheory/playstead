import Foundation
import OSLog

/// TLS decisions are rare and security-relevant.  These records deliberately
/// name only the decision and the local precondition that drove it: never the
/// server URL, certificate bytes, filesystem path, token, or content identity.
private let pinnedTrustLog = Logger(subsystem: "dev.playstead.mac", category: "pinned-trust")

/// An RFC 9457 problem+json error, decoded from a non-2xx API response.
/// Carries the machine-readable `code` field rather than a free-text
/// message string, so callers can branch on it (`device_revoked` vs a
/// generic `unauthorized`, for example) instead of string-matching.
struct APIError: Error, Decodable, Equatable {
    let status: Int
    let code: String
    let title: String?
    let detail: String?
    /// A server-minted, opaque RFC 9457 diagnostic reference. It is not
    /// authorization, content identity, or a retry key; callers may retain it
    /// only through `EligibleDiagnosticEvidence`.
    let correlationID: String?

    private enum CodingKeys: String, CodingKey {
        case code, title, detail
        case correlationID = "correlation_id"
    }

    init(status: Int, code: String, title: String?, detail: String?, correlationID: String? = nil) {
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.correlationID = correlationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = 0
        self.code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.correlationID = try container.decodeIfPresent(String.self, forKey: .correlationID)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.status == rhs.status && lhs.code == rhs.code
    }
}

/// The sole Mac-local representation eligible for correlation diagnostics.
/// Keeping this value to one server-minted UUID makes the evidence boundary
/// incapable of serializing request bodies, credentials, paths, game names,
/// save hashes, or bytes.
struct EligibleDiagnosticEvidence: Equatable {
    let correlationID: String

    init?(correlationID: String?) {
        guard let correlationID, UUID(uuidString: correlationID) != nil else { return nil }
        self.correlationID = correlationID
    }

    init?(problem: APIError) {
        self.init(correlationID: problem.correlationID)
    }

    func serialized() -> String {
        "{\"correlation_id\":\"\(correlationID)\"}"
    }
}

enum APIClientError: Error {
    case notPaired
    case transport(Error)
    case invalidResponse
    case server(APIError)
}

/// A single HTTP response as read by `APIClient.get`.
struct APIResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
}

/// An actor holding one `URLSession` configured with the paired device's
/// bearer credential, per D-10's header-only device auth. Every request
/// attaches `Authorization: Bearer <token>`; the credential itself never
/// appears in a URL or a log line.
///
/// Server-trust evaluation: `pinnedCertificateURL` defaults to
/// `AppPaths.defaultPinnedCertificateURL()` and is passed explicitly by
/// both real construction sites -- `AppEnvironment`'s convenience init
/// and the live-server `UITestBootstrap` session -- both derived from
/// `AppPaths.pinnedCertificate`, the same URL `PairingCoordinator.redeem()`
/// writes the pairing-time trust anchor to. `PinningDelegate` evaluates
/// anchors-only against that file once it exists; when no file exists at
/// that URL (before pairing, or in a test configured with no pinning),
/// evaluation falls back to the platform's default trust handling. See
/// `PinnedTrustWiringTests` for proof the write target and the read
/// target are the same URL, and `PinnedTrustEvaluationTests` for proof
/// pinned evaluation actually diverges from default evaluation.
actor APIClient: NSObject {
    private enum CredentialSource {
        case keychain(KeychainStore)
        case fixed(PairingCredential?)
    }

    private let credentialSource: CredentialSource
    private lazy var defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: PinningDelegate(pinnedCertificateURL: pinnedCertificateURL), delegateQueue: nil)
    }()
    private let sessionOverride: URLSession?
    /// Internal and `nonisolated` (not `private`) so `PinnedTrustWiringTests`
    /// can read it synchronously off the actor without going through async
    /// API — it is an immutable `Sendable let` assigned once in `init`, so
    /// `nonisolated` adds no data-race risk.
    nonisolated let pinnedCertificateURL: URL?
    /// A fixed credential a test can inject instead of `keychain`. Real
    /// macOS Keychain access can fail with `errSecInDarkWake` in a
    /// headless/sandboxed test run (see plan 03-03's SUMMARY) — this
    /// lets `SyncEngineTests` (plan 03-06) drive `APIClient` against a
    /// `URLProtocol` stub without touching the Keychain at all.
    private let credentialOverride: PairingCredential?

    init(
        keychain: KeychainStore,
        pinnedCertificateURL: URL? = AppPaths.defaultPinnedCertificateURL(),
        session: URLSession? = nil,
        credential: PairingCredential? = nil
    ) {
        self.credentialSource = credential.map(CredentialSource.fixed) ?? .keychain(keychain)
        self.pinnedCertificateURL = pinnedCertificateURL
        self.sessionOverride = session
        self.credentialOverride = credential
        super.init()
    }

#if UI_TESTING
    /// An intentionally unpaired UI-profile client with no Security.framework
    /// credential source. Deterministic UI profiles must never fall back to the
    /// login Keychain merely because their fixed credential is absent.
    static func unpairedForUITesting() -> APIClient {
        APIClient(credentialSource: .fixed(nil))
    }

    /// A UI-profile client seeded with a synthetic pairing credential and,
    /// like its unpaired sibling, no Security.framework credential source at
    /// all. A deterministic profile that needs "this Mac is already paired"
    /// world state (`.saveOnlyCopy`) gets it from here.
    ///
    /// Constructing a real `KeychainStore` in a UI profile is what triggers
    /// the login-Keychain authorization prompt that
    /// `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH` exists to gate, so paired
    /// world state must never be a reason to reach for one. The
    /// deterministic UI profile also deliberately opts out of pinning
    /// (`pinnedCertificateURL` stays `nil` below) because it never
    /// contacts a real server.
    static func pairedForUITesting(_ credential: PairingCredential) -> APIClient {
        APIClient(credentialSource: .fixed(credential))
    }

    private init(credentialSource: CredentialSource) {
        self.credentialSource = credentialSource
        self.pinnedCertificateURL = nil
        self.sessionOverride = nil
        self.credentialOverride = nil
        super.init()
    }
#endif

    private var session: URLSession {
        sessionOverride ?? defaultSession
    }

    var credential: PairingCredential? {
        switch credentialSource {
        case .keychain(let keychain):
            return keychain.loadCredential()
        case .fixed(let credential):
            return credential
        }
    }

    /// Uses the already-proven control-plane session for blob transfers too.
    /// A separate session creates a second TLS state machine to keep aligned;
    /// using one retained session makes sync and download share exactly the
    /// same private-CA decision path. Authorization remains request-scoped,
    /// so this does not retain a stale bearer header across pairing changes.
    func makeAuthenticatedDownloadSession() -> URLSession? {
        guard let credential else { return nil }
        if let sessionOverride { return sessionOverride }
        // Pairing may have completed after the control-plane session was first
        // constructed. Build the download session only after the credential
        // and its persisted pin exist, so byte transfer always evaluates the
        // current recovery CA rather than default system trust.
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: PinningDelegate(pinnedCertificateURL: pinnedCertificateURL), delegateQueue: nil)
    }

    /// Performs a `GET` (or, via `headers`, any method that needs a
    /// custom header set) against `path` relative to the paired base
    /// URL, returning status/headers/body. RFC 9457 problem+json bodies
    /// on non-2xx responses are surfaced as `APIClientError.server`.
    ///
    /// `queryItems` (added in plan 03-06 for `GET /api/v1/changes?cursor=…`)
    /// is applied via `URLComponents`, never string-concatenated onto
    /// `path` — `URL.appendingPathComponent` percent-encodes `?`/`=`
    /// literally, which would corrupt a query string built that way.
    func get(path: String, queryItems: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> APIResponse {
        try await send(method: "GET", path: path, queryItems: queryItems, body: nil, headers: headers)
    }

    /// Performs any HTTP method against `path` relative to the paired
    /// base URL, optionally with a JSON body and extra headers (added in
    /// plan 03-08 for `OutboxWorker`'s PUT/POST/PATCH/DELETE curation and
    /// play-session intents, every one of which carries its own
    /// `Idempotency-Key` header per D-20a). Shares `get(path:queryItems:
    /// headers:)`'s error-mapping/response-decoding behavior exactly —
    /// `get` is now a thin `method: "GET"` call through this.
    /// `contentType` (added in plan 04-04 for `SaveUploadLane`'s streamed
    /// binary upload) overrides the default `application/json` sent
    /// whenever `body` is non-nil -- every existing JSON-bodied caller
    /// keeps its current behavior by omitting it.
    func send(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data?,
        headers: [String: String] = [:],
        contentType: String? = nil
    ) async throws -> APIResponse {
        guard let credential = self.credential else {
            throw APIClientError.notPaired
        }

        var components = URLComponents(
            url: credential.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        let headerDict = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value -> (String, String)? in
            guard let k = key as? String, let v = value as? String else { return nil }
            return (k.lowercased(), v)
        })

        if (200..<300).contains(http.statusCode) {
            return APIResponse(status: http.statusCode, headers: headerDict, body: data)
        }

        if let decoded = try? JSONDecoder().decode(APIError.self, from: data) {
            throw APIClientError.server(
                APIError(
                    status: http.statusCode, code: decoded.code, title: decoded.title,
                    detail: decoded.detail, correlationID: decoded.correlationID
                )
            )
        }
        throw APIClientError.server(APIError(status: http.statusCode, code: "unknown", title: nil, detail: nil))
    }
}

/// Pins server-trust evaluation to a captured root CA certificate when
/// one is present on disk; otherwise defers to the platform's default
/// evaluation. See the `APIClient` doc comment for why both paths exist.
///
/// Internal (not `private`) so `PinnedTrustEvaluationTests` can construct
/// it directly under `@testable import Playstead` and exercise
/// `disposition(for:)` without any `URLSession`/`URLProtectionSpace`
/// transport — the whole point of that test is that a system-trusted CI
/// CA cannot make it pass vacuously.
final class PinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let pinnedCertificateURL: URL?

    init(pinnedCertificateURL: URL?) {
        self.pinnedCertificateURL = pinnedCertificateURL
    }

    /// The one decision function both the `URLSessionDelegate` callback
    /// and `PinnedTrustEvaluationTests` execute — no second copy of this
    /// logic exists anywhere else.
    func disposition(for serverTrust: SecTrust?) -> URLSession.AuthChallengeDisposition {
        guard let serverTrust else {
            pinnedTrustLog.error("pinned-trust-decision outcome=default reason=missing-server-trust")
            return .performDefaultHandling
        }
        guard let pinnedCertificateURL else {
            pinnedTrustLog.error("pinned-trust-decision outcome=default reason=missing-pin-location")
            return .performDefaultHandling
        }
        guard let pinnedData = try? Data(contentsOf: pinnedCertificateURL) else {
            pinnedTrustLog.error("pinned-trust-decision outcome=default reason=unreadable-pin")
            return .performDefaultHandling
        }
        guard let pinnedCertificate = SecCertificateCreateWithData(nil, pinnedData as CFData) else {
            pinnedTrustLog.error("pinned-trust-decision outcome=default reason=invalid-pin")
            return .performDefaultHandling
        }

        SecTrustSetAnchorCertificates(serverTrust, [pinnedCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            pinnedTrustLog.notice("pinned-trust-decision outcome=accepted reason=anchors-only-evaluation")
            return .useCredential
        } else {
            pinnedTrustLog.error("pinned-trust-decision outcome=rejected reason=anchors-only-evaluation")
            return .cancelAuthenticationChallenge
        }
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
        let disposition = disposition(for: serverTrust)
        switch disposition {
        case .useCredential:
            completionHandler(.useCredential, serverTrust.map(URLCredential.init(trust:)))
        case .performDefaultHandling:
            completionHandler(.performDefaultHandling, nil)
        default:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// `URLSession.bytes(for:delegate:)` delivers authentication challenges
    /// through its task delegate. Forward that callback through the same
    /// pinned-trust decision used by the control-plane session; otherwise
    /// streamed blob downloads fall back to system trust and reject a valid
    /// self-hosted recovery CA.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}
