import Foundation
import Security

/// Every distinct, actionable outcome the pairing ceremony's server side
/// can produce, mapped from RFC 9457 `code` values (never a message
/// string) so `PairingCoordinator` branches on a value, exactly as
/// `APIError`/`APIClientError` already do for `APIClient` (D-08/PROT-01
/// edge case: `ceremony-failure`).
enum PairingError: Error, Equatable {
    /// 410 `pairing_request_expired` — request a new code.
    case expired
    /// 409 `pairing_request_already_redeemed` — this code was used elsewhere.
    case alreadyRedeemed
    /// 409 `pairing_request_not_approved` — still waiting; approve it in the console.
    case notApproved
    /// 429 `slow_down` — back off, do not hammer (D-12/`Pairing.check_poll_rate/1`).
    case slowDown
    /// 404 — the request id is unknown to the server.
    case notFound
    /// The server denied the request (`GET /requests/:id` → `"denied"`).
    /// Distinct from `.notApproved`, which is a *redeem-time* refusal —
    /// this is the *poll-time* terminal state.
    case denied
    /// A response that could not be decoded as the shape this ceremony expects.
    case invalidResponse
    /// The credential this ceremony redeemed could not be written to the
    /// Keychain. Never `.invalidResponse` — a human reading this needs to
    /// know the network half succeeded and the local half did not.
    case keychainWriteFailed
    /// A transport-level failure (no HTTP response at all). Carries only
    /// `localizedDescription` — never the request body, which may still
    /// hold the plaintext `device_code`.
    case transport(String)
    /// The address the user entered is not `https`, so the ceremony
    /// refused to send a self-generated `device_code` over a channel it
    /// cannot pin. Set by `PairingCoordinator.start(baseURLString:)`
    /// before any network call is made.
    case insecureServerAddress
    /// Pairing completed on the wire but the server's trust anchor could
    /// not be written to `AppPaths.root/pinned-ca.der`, so the ceremony
    /// refuses to report success — the just-stored credential is rolled
    /// back rather than left behind with no pin (VERIFICATION gap 1 / CR-02).
    case certificatePinFailed
}

/// The `POST /api/v1/device-pairing/requests` response (D-07): the
/// server-issued display code and the poll cadence the client must honor.
struct PairingRequestHandle: Equatable {
    let id: String
    let displayCode: String
    let pollInterval: TimeInterval
    let expiresAt: Date
}

/// `GET /api/v1/device-pairing/requests/:id`'s three real statuses.
/// `slow_down` is deliberately not a case here — the server surfaces it as
/// a 429 problem+json, not a status value, so it arrives as a thrown
/// `PairingError.slowDown` instead (see `pairing_controller.ex:show/2`).
enum PairingStatus: Equatable {
    case pending
    case approved
    case denied
}

/// `POST /api/v1/device-pairing/requests/:id/redeem`'s response: exactly
/// the fields `KeychainStore.storeCredential` needs, plus the one
/// credential-derived value that is safe to show a user
/// (`fingerprint_prefix`).
struct RedeemedCredential: Equatable {
    let deviceID: String
    let credential: String
    let fingerprintPrefix: String
}

/// The unauthenticated half of the device-pairing protocol (D-07, D-08).
///
/// `APIClient` cannot be reused here: it attaches a bearer token from the
/// Keychain and throws `.notPaired` with none. This actor covers exactly
/// the three endpoints the ceremony needs before any credential exists,
/// sharing a `URLSessionDelegate` (injected via `session`) with whatever
/// captures the trust anchor during the handshake — so pairing and every
/// later `APIClient` request agree on what is being trusted.
actor PairingClient {
    private let session: URLSession

    /// Production callers supply a session built with a shared
    /// `PinnedCertificateCapture` delegate (see `PairingCoordinator`).
    /// Tests supply a `StubURLProtocol`-backed session instead.
    init(session: URLSession) {
        self.session = session
    }

    /// 32 cryptographically random bytes, base64url-encoded, generated
    /// once per ceremony attempt and held only in memory by the caller
    /// (never persisted, logged, or written anywhere but the redeem body).
    static func generateDeviceCode(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed for the pairing device code")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `POST /api/v1/device-pairing/requests` — deliberately unauthenticated
    /// (D-07): the client has no credential yet.
    func createRequest(
        baseURL: URL,
        deviceCode: String,
        deviceName: String,
        platform: String,
        appVersion: String
    ) async throws -> PairingRequestHandle {
        struct RequestBody: Encodable {
            let deviceCode: String
            let deviceName: String
            let platform: String
            let appVersion: String
            enum CodingKeys: String, CodingKey {
                case deviceCode = "device_code"
                case deviceName = "device_name"
                case platform
                case appVersion = "app_version"
            }
        }
        let body = try JSONEncoder().encode(RequestBody(
            deviceCode: deviceCode, deviceName: deviceName, platform: platform, appVersion: appVersion
        ))
        let (data, response) = try await perform(
            method: "POST",
            url: baseURL.appendingPathComponent("api/v1/device-pairing/requests"),
            body: body
        )
        try Self.throwIfNotSuccess(response: response, data: data)

        struct Payload: Decodable {
            let id: String
            let displayCode: String
            let pollInterval: Double
            let expiresAt: String
            enum CodingKeys: String, CodingKey {
                case id
                case displayCode = "display_code"
                case pollInterval = "poll_interval"
                case expiresAt = "expires_at"
            }
        }
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let expiresAt = Self.parseDate(payload.expiresAt)
        else {
            throw PairingError.invalidResponse
        }
        return PairingRequestHandle(
            id: payload.id, displayCode: payload.displayCode,
            pollInterval: payload.pollInterval, expiresAt: expiresAt
        )
    }

    /// `GET /api/v1/device-pairing/requests/:id` — also unauthenticated;
    /// the id alone carries no capability to redeem (only `device_code` does).
    func pollStatus(baseURL: URL, requestID: String) async throws -> PairingStatus {
        let (data, response) = try await perform(
            method: "GET",
            url: baseURL.appendingPathComponent("api/v1/device-pairing/requests/\(requestID)"),
            body: nil
        )
        try Self.throwIfNotSuccess(response: response, data: data)

        struct Payload: Decodable { let status: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw PairingError.invalidResponse
        }
        switch payload.status {
        case "pending": return .pending
        case "approved": return .approved
        case "denied": return .denied
        default: throw PairingError.invalidResponse
        }
    }

    /// `POST /api/v1/device-pairing/requests/:id/redeem` — unauthenticated
    /// (D-08): the client has no credential yet, only the `device_code`
    /// it generated at request time, which is this call's only secret.
    func redeem(baseURL: URL, requestID: String, deviceCode: String) async throws -> RedeemedCredential {
        struct RequestBody: Encodable {
            let deviceCode: String
            enum CodingKeys: String, CodingKey { case deviceCode = "device_code" }
        }
        let body = try JSONEncoder().encode(RequestBody(deviceCode: deviceCode))
        let (data, response) = try await perform(
            method: "POST",
            url: baseURL.appendingPathComponent("api/v1/device-pairing/requests/\(requestID)/redeem"),
            body: body
        )
        try Self.throwIfNotSuccess(response: response, data: data)

        struct Payload: Decodable {
            let deviceID: String
            let credential: String
            let fingerprintPrefix: String
            enum CodingKeys: String, CodingKey {
                case deviceID = "device_id"
                case credential
                case fingerprintPrefix = "fingerprint_prefix"
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw PairingError.invalidResponse
        }
        return RedeemedCredential(
            deviceID: payload.deviceID, credential: payload.credential,
            fingerprintPrefix: payload.fingerprintPrefix
        )
    }

    // MARK: - Transport

    private func perform(method: String, url: URL, body: Data?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            return try await session.data(for: request)
        } catch {
            throw PairingError.transport(error.localizedDescription)
        }
    }

    /// Maps a non-2xx response to the exact typed `PairingError` the
    /// server distinguished, from its RFC 9457 `code` field — never from
    /// the free-text `title`/`detail`.
    private static func throwIfNotSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }
        guard !(200..<300).contains(http.statusCode) else { return }

        struct Problem: Decodable { let code: String? }
        let code = (try? JSONDecoder().decode(Problem.self, from: data))?.code

        switch (http.statusCode, code) {
        case (410, _): throw PairingError.expired
        case (409, "pairing_request_already_redeemed"): throw PairingError.alreadyRedeemed
        case (409, "pairing_request_not_approved"): throw PairingError.notApproved
        case (429, _): throw PairingError.slowDown
        case (404, _): throw PairingError.notFound
        default: throw PairingError.invalidResponse
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}
