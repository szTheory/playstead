import Foundation

/// An RFC 9457 problem+json error, decoded from a non-2xx API response.
/// Carries the machine-readable `code` field rather than a free-text
/// message string, so callers can branch on it (`device_revoked` vs a
/// generic `unauthorized`, for example) instead of string-matching.
struct APIError: Error, Decodable, Equatable {
    let status: Int
    let code: String
    let title: String?
    let detail: String?

    private enum CodingKeys: String, CodingKey {
        case code, title, detail
    }

    init(status: Int, code: String, title: String?, detail: String?) {
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = 0
        self.code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.status == rhs.status && lhs.code == rhs.code
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
/// Server-trust evaluation: Phase 1 pins the pairing-time root CA via a
/// `URLSessionDelegate`. This tracer plan does not yet ship the pairing
/// ceremony that captures that pinned certificate, so `APIClient` uses
/// the platform's default trust evaluation when no pinned certificate is
/// present on disk, and switches to pinned evaluation automatically once
/// one is (`AppPaths.root/pinned-ca.der`, written by a future pairing
/// plan). This keeps the client usable against a Caddy-internal-CA
/// deployment today without silently downgrading trust once pairing
/// ships its certificate capture.
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
                APIError(status: http.statusCode, code: decoded.code, title: decoded.title, detail: decoded.detail)
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
final class PinningDelegate: NSObject, URLSessionDelegate {
    let pinnedCertificateURL: URL?

    init(pinnedCertificateURL: URL?) {
        self.pinnedCertificateURL = pinnedCertificateURL
    }

    /// The one decision function both the `URLSessionDelegate` callback
    /// and `PinnedTrustEvaluationTests` execute — no second copy of this
    /// logic exists anywhere else.
    func disposition(for serverTrust: SecTrust?) -> URLSession.AuthChallengeDisposition {
        guard
            let serverTrust,
            let pinnedCertificateURL,
            let pinnedData = try? Data(contentsOf: pinnedCertificateURL),
            let pinnedCertificate = SecCertificateCreateWithData(nil, pinnedData as CFData)
        else {
            return .performDefaultHandling
        }

        SecTrustSetAnchorCertificates(serverTrust, [pinnedCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            return .useCredential
        } else {
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
        switch disposition(for: serverTrust) {
        case .useCredential:
            completionHandler(.useCredential, serverTrust.map(URLCredential.init(trust:)))
        case .performDefaultHandling:
            completionHandler(.performDefaultHandling, nil)
        default:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
