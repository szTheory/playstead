import Foundation
import OSLog

/// One privacy-safe terminal summary per pairing attempt. It intentionally
/// has no fields for codes, request IDs, credentials, certificates, URLs,
/// paths, filenames, identities, or library/save data.
struct PairingOutcomeRecord: Equatable {
    let correlationID: String
    let stage: String
    let outcome: String
    let reasonCode: String
    let retryable: Bool
    let durationMilliseconds: Int
}

protocol PairingOutcomeRecording: AnyObject {
    func record(_ outcome: PairingOutcomeRecord)
}

/// A single unified-log decision record is the durable local diagnostic
/// seam. It is deliberately neither analytics nor verbose activity logging.
final class OSLogPairingOutcomeRecorder: PairingOutcomeRecording {
    private let logger = Logger(subsystem: "dev.playstead.mac", category: "pairing-outcome")

    func record(_ outcome: PairingOutcomeRecord) {
        logger.notice(
            "pairing_outcome correlation_id=\(outcome.correlationID, privacy: .public) stage=\(outcome.stage, privacy: .public) outcome=\(outcome.outcome, privacy: .public) reason_code=\(outcome.reasonCode, privacy: .public) retryable=\(outcome.retryable, privacy: .public) duration_ms=\(outcome.durationMilliseconds, privacy: .public)"
        )
    }
}

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
    /// Privacy-reduced local evidence for the terminal or retryable server
    /// Problem that affected this ceremony. This is intentionally separate
    /// from state and credentials, so it cannot influence authorization,
    /// device-code lifecycle, certificate pinning, or retry identity.
    private(set) var lastFailureDiagnosticEvidence: EligibleDiagnosticEvidence?

    private let client: PairingClient
    private let keychain: KeychainStore
    private let certificateCapture: PinnedCertificateCapture?
    /// Internal (not `private`) so `PinnedTrustWiringTests` can compare
    /// this write target against `APIClient.pinnedCertificateURL`'s read
    /// target by live-object equality.
    let pinnedCertificateURL: URL?
    private let deviceName: String
    private let platform: String
    private let appVersion: String
    private let deviceCodeGenerator: () -> String
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void
    /// The cap the poll interval backs off to at most (D-07/D-12's
    /// `slow_down`): doubles on every 429, never grows without bound.
    private let maxPollInterval: TimeInterval
    private let outcomeRecorder: PairingOutcomeRecording
    /// The application owns what happens after a credential is durable.  The
    /// ceremony only reports its terminal success; production injects the
    /// first sync so a newly paired library does not remain empty until the
    /// next relaunch or manual refresh.
    private let afterPairing: () async -> Void

    private var pollTask: Task<Void, Never>?
    private var deviceCode: String?
    private var baseURL: URL?
    private var requestID: String?
    /// Monotonic ceremony generation. This — not `pollTask?.cancel()` — is
    /// what makes `cancel()` authoritative: `pollTask?.cancel()` only sets
    /// Swift's cooperative cancellation flag, but `start()`, `pollLoop()`
    /// and `redeem()` are ordinary (non-weak) method-call frames, so an
    /// in-flight `URLSession` call they are suspended in always completes
    /// regardless of that flag. `cancel()` increments this first; every
    /// commit point (a `state` assignment, a Keychain write, a pin write,
    /// or starting a new poll loop) compares the generation it started
    /// under against the current value immediately after its `await`
    /// resumes, and abandons the result if they differ (VERIFICATION
    /// gap 2 / CR-01).
    private var generation = 0
    private var attemptCorrelationID: String?
    private var attemptStartedAt: Date?

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
        maxPollInterval: TimeInterval = 60,
        outcomeRecorder: PairingOutcomeRecording = OSLogPairingOutcomeRecorder(),
        afterPairing: @escaping () async -> Void = {}
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
        self.outcomeRecorder = outcomeRecorder
        self.afterPairing = afterPairing
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

        beginAttempt()

        guard
            let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme, !scheme.isEmpty,
            let host = url.host, !host.isEmpty
        else {
            fail(.invalidResponse, stage: "validation")
            return
        }

        // Refuse every non-https scheme before a device code is generated
        // or a single network call is made: a downgraded ceremony must
        // never send the self-generated `device_code` over a channel it
        // cannot pin, and a plaintext handshake never triggers the TLS
        // challenge `PinnedCertificateCapture` depends on
        // (VERIFICATION gap 1 / CR-02).
        guard url.scheme?.lowercased() == "https" else {
            fail(.insecureServerAddress, stage: "validation")
            return
        }

        baseURL = url
        lastFailureDiagnosticEvidence = nil
        state = .requesting
        let code = deviceCodeGenerator()
        deviceCode = code
        let myGeneration = generation

        do {
            let handle = try await client.createRequest(
                baseURL: url, deviceCode: code, deviceName: deviceName, platform: platform, appVersion: appVersion
            )
            // A cancelled ceremony must neither resurrect a state nor
            // start an orphaned poll loop against a request nothing will
            // ever redeem (VERIFICATION gap 2 / CR-01).
            guard myGeneration == generation else { return }
            requestID = handle.id
            state = .awaitingApproval(displayCode: handle.displayCode, expiresAt: handle.expiresAt)
            startPolling(interval: handle.pollInterval)
        } catch let error as PairingError {
            guard myGeneration == generation else { return }
            await recordFailureDiagnosticEvidence()
            fail(error, stage: "request")
        } catch {
            guard myGeneration == generation else { return }
            fail(.transport(error.localizedDescription), stage: "request")
        }
    }

    /// Stops the poll loop and returns to `.idle` — the user closing the
    /// sheet, or starting over, must stop polling rather than let it run
    /// against a request nothing will ever redeem.
    func cancel() {
        // First statement, always: every commit point compares against
        // this value, so incrementing it here is what makes every
        // in-flight `await` below abandon its result once it resumes.
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        state = .idle
        deviceCode = nil
        requestID = nil
        baseURL = nil
        finishAttempt(stage: "cancel", outcome: "cancelled", reasonCode: "user_cancelled", retryable: true)
    }

    private func startPolling(interval: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop(initialInterval: interval)
        }
    }

    private func pollLoop(initialInterval: TimeInterval) async {
        let myGeneration = generation
        var interval = initialInterval
        while !Task.isCancelled {
            await sleep(interval)
            if Task.isCancelled { return }
            guard myGeneration == generation else { return }

            guard case .awaitingApproval(_, let expiresAt) = state else { return }
            if now() >= expiresAt {
                fail(.expired, stage: "poll")
                return
            }
            guard let baseURL, let requestID else { return }

            do {
                let status = try await client.pollStatus(baseURL: baseURL, requestID: requestID)
                // A response for a cancelled ceremony must never commit
                // anything — most importantly, an `.approved` result must
                // never reach `redeem()` after `cancel()` has already run
                // (VERIFICATION gap 2 / CR-01).
                guard myGeneration == generation else { return }
                switch status {
                case .pending:
                    continue
                case .approved:
                    await redeem()
                    return
                case .denied:
                    fail(.denied, stage: "poll")
                    return
                }
            } catch PairingError.slowDown {
                guard myGeneration == generation else { return }
                await recordFailureDiagnosticEvidence()
                // D-07/D-12: never retry immediately on a rate-limit
                // refusal — double the interval for the next attempt,
                // capped, so the ceremony backs off rather than tripping
                // `Pairing.check_poll_rate/1` again next cycle.
                interval = min(interval * 2, maxPollInterval)
                continue
            } catch let error as PairingError {
                guard myGeneration == generation else { return }
                await recordFailureDiagnosticEvidence()
                fail(error, stage: "poll")
                return
            } catch {
                guard myGeneration == generation else { return }
                fail(.transport(error.localizedDescription), stage: "poll")
                return
            }
        }
    }

    private func redeem() async {
        guard let baseURL, let requestID, let deviceCode else {
            fail(.invalidResponse, stage: "redeem")
            return
        }
        let myGeneration = generation
        state = .redeeming
        do {
            let redeemed = try await client.redeem(baseURL: baseURL, requestID: requestID, deviceCode: deviceCode)
            // The hardest window: cancel() may have already run while this
            // call was in flight. If so, the server-issued credential is
            // simply abandoned — never constructed into a stored
            // credential, never written to the Keychain, never pinned,
            // and no `state` assignment below runs (VERIFICATION gap 2 /
            // CR-01).
            guard myGeneration == generation else { return }
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
                        fail(.certificatePinFailed, stage: "redeem")
                        return
                    }
                }
                state = .paired(deviceID: redeemed.deviceID)
                finishAttempt(stage: "redeem", outcome: "succeeded", reasonCode: "paired", retryable: false)
                // Do not make pairing success wait on a potentially slow
                // snapshot. The credential is already durable, and this
                // continuation gives a fresh library its first sync without
                // requiring a relaunch or a user-discovered refresh action.
                Task { [afterPairing] in
                    await afterPairing()
                }
            case .failure:
                fail(.keychainWriteFailed, stage: "redeem")
            }
        } catch let error as PairingError {
            guard myGeneration == generation else { return }
            await recordFailureDiagnosticEvidence()
            fail(error, stage: "redeem")
        } catch {
            guard myGeneration == generation else { return }
            fail(.transport(error.localizedDescription), stage: "redeem")
        }
    }

    private func beginAttempt() {
        attemptCorrelationID = UUID().uuidString.lowercased()
        attemptStartedAt = now()
    }

    private func fail(_ error: PairingError, stage: String) {
        state = .failed(error)
        finishAttempt(
            stage: stage,
            outcome: "failed",
            reasonCode: Self.outcomeReasonCode(for: error),
            retryable: Self.isRetryable(error)
        )
    }

    private func finishAttempt(stage: String, outcome: String, reasonCode: String, retryable: Bool) {
        guard let correlationID = attemptCorrelationID, let startedAt = attemptStartedAt else { return }
        attemptCorrelationID = nil
        attemptStartedAt = nil
        outcomeRecorder.record(PairingOutcomeRecord(
            correlationID: correlationID,
            stage: stage,
            outcome: outcome,
            reasonCode: reasonCode,
            retryable: retryable,
            durationMilliseconds: max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
        ))
    }

    private static func outcomeReasonCode(for error: PairingError) -> String {
        switch error {
        case .expired: return "pairing_request_expired"
        case .alreadyRedeemed: return "pairing_request_already_redeemed"
        case .notApproved: return "pairing_request_not_approved"
        case .slowDown: return "slow_down"
        case .notFound: return "pairing_request_not_found"
        case .denied: return "pairing_request_denied"
        case .invalidResponse: return "invalid_response"
        case .keychainWriteFailed: return "keychain_write_failed"
        case .transport: return "transport_failed"
        case .insecureServerAddress: return "insecure_server_address"
        case .certificatePinFailed: return "certificate_pin_failed"
        case .certificateTrustFailed: return "certificate_trust_rejected"
        }
    }

    private static func isRetryable(_ error: PairingError) -> Bool {
        switch error {
        case .alreadyRedeemed, .denied:
            return false
        default:
            return true
        }
    }

    // MARK: - Defaults

    private func recordFailureDiagnosticEvidence() async {
        lastFailureDiagnosticEvidence = await client.lastFailureDiagnosticEvidence
    }

    nonisolated static func defaultDeviceName() -> String {
        // WR-01: the UI-test device-name override is a confused-deputy vector
        // if it is reachable from a Release build -- any process could set
        // this environment variable and steer what name a Release Mac pairs
        // under. Gated to DEBUG so the override stays available to the
        // Debug-configuration UI test target (PairingCeremonyTests sets this
        // exact key) while a Release binary reads only the real host name.
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_PAIRING_DEVICE_NAME"] {
            return override
        }
        return Host.current().localizedName ?? "Mac"
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    nonisolated static func defaultAppVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    private static func defaultSleep(_ interval: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
    }
}
