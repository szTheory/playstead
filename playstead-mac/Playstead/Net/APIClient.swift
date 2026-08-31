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
    private let keychain: KeychainStore
    private lazy var defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: PinningDelegate(pinnedCertificateURL: pinnedCertificateURL), delegateQueue: nil)
    }()
    private let sessionOverride: URLSession?
    private let pinnedCertificateURL: URL?
    /// A fixed credential a test can inject instead of `keychain`. Real
    /// macOS Keychain access can fail with `errSecInDarkWake` in a
    /// headless/sandboxed test run (see plan 03-03's SUMMARY) — this
    /// lets `SyncEngineTests` (plan 03-06) drive `APIClient` against a
    /// `URLProtocol` stub without touching the Keychain at all.
    private let credentialOverride: PairingCredential?

    init(
        keychain: KeychainStore,
        pinnedCertificateURL: URL? = nil,
        session: URLSession? = nil,
        credential: PairingCredential? = nil
    ) {
        self.keychain = keychain
        self.pinnedCertificateURL = pinnedCertificateURL
        self.sessionOverride = session
        self.credentialOverride = credential
        super.init()
    }

    private var session: URLSession {
        sessionOverride ?? defaultSession
    }

    var credential: PairingCredential? {
        credentialOverride ?? keychain.loadCredential()
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
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
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
/// evaluation. See the `APIClient` doc comment for why both paths exist
/// in this tracer plan.
private final class PinningDelegate: NSObject, URLSessionDelegate {
    let pinnedCertificateURL: URL?

    init(pinnedCertificateURL: URL?) {
        self.pinnedCertificateURL = pinnedCertificateURL
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust,
            let pinnedCertificateURL,
            let pinnedData = try? Data(contentsOf: pinnedCertificateURL),
            let pinnedCertificate = SecCertificateCreateWithData(nil, pinnedData as CFData)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [pinnedCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
