import Foundation

/// The pairing ceremony's own state machine, exactly as `SaveSessionCoordinator`
/// was extracted from `play()`: a plain type a test constructs directly, with
/// no `URLSession`, no SwiftUI, and no Keychain construction of its own — all
/// three are injected, so `PairingView` drives this and nothing else, and no
/// step of the ceremony can live inline in a `private @MainActor` view method
/// (WINDOWS #37, #45's own failure mode).
///
/// ```
/// idle -> requesting -> awaitingApproval(displayCode, expiresAt) -> redeeming -> paired(deviceID)
///                                                                             \-> failed(PairingError)
/// ```
enum PairingState: Equatable {
    case idle
    case requesting
    case awaitingApproval(displayCode: String, expiresAt: Date)
    case redeeming
    case paired(deviceID: String)
    case failed(PairingError)
}

@MainActor
@Observable
final class PairingCoordinator {
    private(set) var state: PairingState = .idle

    private let client: PairingClient
    private let keychain: KeychainStore
    private let certificateCapture: PinnedCertificateCapture?
    private let pinnedCertificateURL: URL?
    private let deviceName: String
    private let platform: String
    private let appVersion: String
    private let deviceCodeGenerator: () -> String
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void
    /// The cap the poll interval backs off to at most (D-07/D-12's
    /// `slow_down`): doubles on every 429, never grows without bound.
    private let maxPollInterval: TimeInterval

    private var pollTask: Task<Void, Never>?
    private var deviceCode: String?
    private var baseURL: URL?
    private var requestID: String?

    init(
        client: PairingClient,
        keychain: KeychainStore,
        certificateCapture: PinnedCertificateCapture? = nil,
        pinnedCertificateURL: URL? = nil,
        deviceName: String = PairingCoordinator.defaultDeviceName(),
        platform: String = "macOS",
        appVersion: String = PairingCoordinator.defaultAppVersion(),
        deviceCodeGenerator: @escaping () -> String = { PairingClient.generateDeviceCode() },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async -> Void = PairingCoordinator.defaultSleep,
        maxPollInterval: TimeInterval = 60
    ) {
        self.client = client
        self.keychain = keychain
        self.certificateCapture = certificateCapture
        self.pinnedCertificateURL = pinnedCertificateURL
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
        self.deviceCodeGenerator = deviceCodeGenerator
        self.now = now
        self.sleep = sleep
        self.maxPollInterval = maxPollInterval
    }

    /// Starts a fresh ceremony against `baseURLString`. A no-op while a
    /// ceremony is already in flight (`.requesting`/`.awaitingApproval`/
    /// `.redeeming`) — the caller must `cancel()` first, exactly as
    /// `SaveSessionCoordinator.begin` refuses to replace an open session.
    func start(baseURLString: String) async {
        switch state {
        case .requesting, .awaitingApproval, .redeeming:
            return
        case .idle, .paired, .failed:
            break
        }

        guard
            let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme, !scheme.isEmpty,
            let host = url.host, !host.isEmpty
        else {
            state = .failed(.invalidResponse)
            return
        }

        // Refuse every non-https scheme before a device code is generated
        // or a single network call is made: a downgraded ceremony must
        // never send the self-generated `device_code` over a channel it
        // cannot pin, and a plaintext handshake never triggers the TLS
        // challenge `PinnedCertificateCapture` depends on
        // (VERIFICATION gap 1 / CR-02).
        guard url.scheme?.lowercased() == "https" else {
            state = .failed(.insecureServerAddress)
            return
        }

        baseURL = url
        state = .requesting
        let code = deviceCodeGenerator()
        deviceCode = code

        do {
            let handle = try await client.createRequest(
                baseURL: url, deviceCode: code, deviceName: deviceName, platform: platform, appVersion: appVersion
            )
            requestID = handle.id
            state = .awaitingApproval(displayCode: handle.displayCode, expiresAt: handle.expiresAt)
            startPolling(interval: handle.pollInterval)
        } catch let error as PairingError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    /// Stops the poll loop and returns to `.idle` — the user closing the
    /// sheet, or starting over, must stop polling rather than let it run
    /// against a request nothing will ever redeem.
    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
        deviceCode = nil
        requestID = nil
        baseURL = nil
    }

    private func startPolling(interval: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop(initialInterval: interval)
        }
    }

    private func pollLoop(initialInterval: TimeInterval) async {
        var interval = initialInterval
        while !Task.isCancelled {
            await sleep(interval)
            if Task.isCancelled { return }

            guard case .awaitingApproval(_, let expiresAt) = state else { return }
            if now() >= expiresAt {
                state = .failed(.expired)
                return
            }
            guard let baseURL, let requestID else { return }

            do {
                switch try await client.pollStatus(baseURL: baseURL, requestID: requestID) {
                case .pending:
                    continue
                case .approved:
                    await redeem()
                    return
                case .denied:
                    state = .failed(.denied)
                    return
                }
            } catch PairingError.slowDown {
                // D-07/D-12: never retry immediately on a rate-limit
                // refusal — double the interval for the next attempt,
                // capped, so the ceremony backs off rather than tripping
                // `Pairing.check_poll_rate/1` again next cycle.
                interval = min(interval * 2, maxPollInterval)
                continue
            } catch let error as PairingError {
                state = .failed(error)
                return
            } catch {
                state = .failed(.transport(error.localizedDescription))
                return
            }
        }
    }

    private func redeem() async {
        guard let baseURL, let requestID, let deviceCode else {
            state = .failed(.invalidResponse)
            return
        }
        state = .redeeming
        do {
            let redeemed = try await client.redeem(baseURL: baseURL, requestID: requestID, deviceCode: deviceCode)
            let credential = PairingCredential(deviceID: redeemed.deviceID, baseURL: baseURL, token: redeemed.credential)
            switch keychain.storeCredential(credential) {
            case .success:
                // Written strictly after the credential is durable: a
                // failed pairing must never leave a pin behind that would
                // break a later attempt against a re-issued certificate.
                //
                // When both `certificateCapture` and `pinnedCertificateURL`
                // are configured (always true in production —
                // `makePairingCoordinator()` supplies both), the pin write
                // gates success: a false return means the trust anchor
                // never landed on disk, so the credential just stored is
                // rolled back and the ceremony ends terminal rather than
                // reporting `.paired` with no pin (VERIFICATION gap 1 /
                // CR-02). When either is `nil` the coordinator was
                // constructed with no pinning configured — a test-only
                // configuration — so pairing proceeds unpinned.
                if let certificateCapture, let pinnedCertificateURL {
                    guard certificateCapture.writeCapturedCertificate(to: pinnedCertificateURL) else {
                        keychain.deleteCredential()
                        state = .failed(.certificatePinFailed)
                        return
                    }
                }
                state = .paired(deviceID: redeemed.deviceID)
            case .failure:
                state = .failed(.keychainWriteFailed)
            }
        } catch let error as PairingError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    // MARK: - Defaults

    nonisolated static func defaultDeviceName() -> String {
        ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_PAIRING_DEVICE_NAME"] ?? Host.current().localizedName ?? "Mac"
    }

    nonisolated static func defaultAppVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    private static func defaultSleep(_ interval: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
    }
}
