import Foundation
import CryptoKit

/// Privacy-safe diagnostic vocabulary for retryable save upload failures.
/// It intentionally excludes underlying error descriptions, URLs, IDs,
/// response bodies, paths, and server-generated correlation values.
enum SaveUploadFailureCause: Equatable, Sendable {
    case none
    case localState
    case notPaired
    case idempotencyConflict
    case serverNotFound
    case transportConnectivity
    case transportTimeout
    case transportTLS
    case transportOther
    case invalidResponse
    case http408
    case http429
    case http400
    case http401
    case http403
    case http404
    case http409
    case http413
    case http422
    case http5xx
    case httpOther

    static func classify(_ error: Error) -> Self {
        guard let clientError = error as? APIClientError else { return .localState }
        switch clientError {
        case .notPaired:
            return .notPaired
        case .transport(let underlying):
            let nsError = underlying as NSError
            guard nsError.domain == NSURLErrorDomain else { return .transportOther }
            let code = URLError.Code(rawValue: nsError.code)
            switch code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
                 .notConnectedToInternet, .cannotLoadFromNetwork, .dataNotAllowed:
                return .transportConnectivity
            case .timedOut:
                return .transportTimeout
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
                 .clientCertificateRejected, .clientCertificateRequired:
                return .transportTLS
            default:
                return .transportOther
            }
        case .invalidResponse:
            return .invalidResponse
        case .server(let problem):
            switch problem.code {
            case "idempotency_key_conflict": return .idempotencyConflict
            case "not_found": return .serverNotFound
            default: break
            }
            switch problem.status {
            case 400: return .http400
            case 401: return .http401
            case 403: return .http403
            case 404: return .http404
            case 408: return .http408
            case 409: return .http409
            case 413: return .http413
            case 422: return .http422
            case 429: return .http429
            case 500...: return .http5xx
            default: return .httpOther
            }
        }
    }
}

/// A tightly allowlisted view of an RFC 9457 response. Server-provided
/// `code` text is never retained verbatim; only the two reliability-fixture
/// classes and a generic fallback can cross the diagnostic boundary.
enum SaveUploadProblemCode: String, Equatable, Sendable {
    case serviceUnavailable = "service_unavailable"
    case idempotencyKeyConflict = "idempotency_key_conflict"
    case other
}

struct SaveUploadProblemEvidence: Equatable, Sendable {
    let status: Int
    let code: SaveUploadProblemCode

    init?(error: Error) {
        guard case APIClientError.server(let problem) = error,
              (400...599).contains(problem.status) else { return nil }
        self.status = problem.status
        switch problem.code {
        case SaveUploadProblemCode.serviceUnavailable.rawValue:
            self.code = .serviceUnavailable
        case SaveUploadProblemCode.idempotencyKeyConflict.rawValue:
            self.code = .idempotencyKeyConflict
        default:
            self.code = .other
        }
    }
}

struct SaveUploadFailureEvidence: Sendable {
    let classification: SaveUploadFailureClassification
    let cause: SaveUploadFailureCause
    let status: Int?
    let problemCode: SaveUploadProblemCode?
    let correlationID: String?
}

enum SaveUploadError: Error, Equatable {
    case missingLocalBytes
    case missingLine
    case missingRevision
}

/// A lock-guarded cell holding the lane's most recent failure
/// classification.
///
/// It exists because the reader -- `AppEnvironment
/// .saveUploadFailureClassification()`, which `OnlyCopyEscalationPanel`
/// consults during a synchronous main-actor read -- cannot `await` into
/// an actor. The lane owns the value; this cell is only the
/// synchronously-readable window onto it.
final class SaveUploadClassificationCell: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: SaveUploadFailureClassification = .none

    var value: SaveUploadFailureClassification {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ value: SaveUploadFailureClassification) {
        lock.lock()
        _value = value
        lock.unlock()
    }
}

/// Synchronous, privacy-reduced view of the most recent server diagnostic
/// reference. It deliberately shares none of the lane's save identifiers,
/// local paths, hashes, or bytes.
final class SaveUploadDiagnosticEvidenceCell: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: EligibleDiagnosticEvidence?

    var value: EligibleDiagnosticEvidence? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ value: EligibleDiagnosticEvidence?) {
        lock.lock()
        _value = value
        lock.unlock()
    }
}

final class SaveUploadProblemEvidenceCell: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: SaveUploadProblemEvidence?

    var value: SaveUploadProblemEvidence? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ value: SaveUploadProblemEvidence?) {
        lock.lock()
        _value = value
        lock.unlock()
    }
}

/// Drains locally-captured save revisions to the server: a streamed
/// upload, then the idempotent metadata commit, in that order, for one
/// revision at a time (D-16, D-32). A dedicated lane — not a priority
/// band inside the curation `OutboxWorker` — so it is drained ahead of
/// the curation outbox and downloads regardless of what else is
/// queued, per D-32.
///
/// Reuses `OutboxWorker`'s in-order, stop-on-retry drain shape. Because
/// actors are reentrant at `await`, a per-revision in-flight gate makes
/// overlapping `drainOnce()` calls await the same upload instead of
/// sending the revision twice before its local `durability` changes. A
/// revision that fails never reaches a silent terminal state (D-32) — it
/// stays `queued` (visible, never quarantined-to-silence) and is retried
/// on the next `drainOnce()` call.
actor SaveUploadLane {
    private let apiClient: APIClient
    private let saveStore: SaveStore

    /// Per-revision attempt count and next-eligible time, following
    /// `Outbox.maxAttempts`/`retryDelay(forAttempt:)`'s exact curve
    /// (task 2's `<action>`) — but where `OutboxWorker` quarantines an
    /// entry once the cap is reached, this lane never does: once
    /// `Outbox.maxAttempts` is reached the delay is held at its capped
    /// value and the entry keeps retrying forever, because a revision
    /// that exists on exactly one device is the most dangerous state in
    /// the product (D-32) and must never go silent.
    private var attemptCounts: [String: Int] = [:]
    private var nextEligibleAt: [String: Date] = [:]
    private var inFlightRevisionIDs: Set<String> = []
    private var inFlightRevisionWaiters: [String: [CheckedContinuation<RevisionAttemptResult, Never>]] = [:]
    private var transientTestFailureEvidence: (revisionID: String, evidence: SaveUploadFailureEvidence)?

    private struct RevisionAttemptResult: Sendable {
        let sent: Int
        let stoppedForRetry: Bool
        let failureClassification: SaveUploadFailureClassification
        let saveUploadFailureCause: SaveUploadFailureCause
    }

    private let classificationCell = SaveUploadClassificationCell()
    private let diagnosticEvidenceCell = SaveUploadDiagnosticEvidenceCell()
    private let problemEvidenceCell = SaveUploadProblemEvidenceCell()

    init(apiClient: APIClient, saveStore: SaveStore) {
        self.apiClient = apiClient
        self.saveStore = saveStore
    }

    /// D-32/D-40: what this lane's most recent attempt actually failed
    /// with, in the escalation vocabulary `OnlyCopyEscalationPanel`
    /// speaks. `.none` until something fails, and back to `.none` the
    /// moment a revision uploads successfully.
    ///
    /// This is the output WINDOWS #40 recorded as missing: without it,
    /// `AppEnvironment.saveUploadFailureClassification()` could only ever
    /// return `.offlineQueue` or `.none`, so the four genuinely unfixable
    /// reasons were permanently unreachable in the shipped app however
    /// the server actually responded.
    nonisolated var lastFailureClassification: SaveUploadFailureClassification {
        classificationCell.value
    }

    /// The opaque server reference from this lane's most recent retryable or
    /// terminal Problem response, reduced to its allowlisted diagnostic form.
    /// A success clears it; transport failures have no server value to retain.
    nonisolated var lastFailureDiagnosticEvidence: EligibleDiagnosticEvidence? {
        diagnosticEvidenceCell.value
    }

    nonisolated var lastFailureProblemEvidence: SaveUploadProblemEvidence? {
        problemEvidenceCell.value
    }

    func transientFailureEvidence() -> SaveUploadFailureEvidence? {
        transientTestFailureEvidence?.evidence
    }

    static func diagnosticEvidence(for error: Error) -> EligibleDiagnosticEvidence? {
        guard case APIClientError.server(let problem) = error else { return nil }
        return EligibleDiagnosticEvidence(problem: problem)
    }

    /// Maps one upload failure onto D-40's escalation vocabulary.
    ///
    /// The rule is deliberately conservative: only a failure this Mac
    /// genuinely cannot resolve by retrying escalates. Anything
    /// retryable -- transport loss, 5xx, rate limiting, an unpaired
    /// client -- stays `.none`, because escalating a condition that
    /// fixes itself is exactly what D-40 forbids.
    static func classify(_ error: Error) -> SaveUploadFailureClassification {
        guard case APIClientError.server(let apiError) = error else {
            // `.transport`, `.invalidResponse`, `.notPaired`, and the
            // lane's own `missingLocalBytes`/`missingLine` are all
            // either retryable or local bookkeeping, never one of
            // D-40's four server-side unfixable reasons.
            return .none
        }

        // The machine-readable `code` is the contract (D-22); status is
        // only the fallback for a response that carried no known code.
        switch apiError.code {
        case "device_revoked", "unauthorized":
            return .revokedAuth
        case "capability_incompatible":
            return .capabilitySkew
        case "save_binding_incompatible", "save_revision_digest_mismatch", "save_parent_unknown",
             "save_revision_immutable", "save_branch_limit_exceeded":
            return .compatibilityRejection
        case "slow_down", "rate_limited", "internal_error":
            return .none
        default:
            break
        }

        switch apiError.status {
        case 401, 403:
            return .revokedAuth
        case 408, 429:
            return .none
        case 500...:
            return .none
        case 400..<500:
            return .serverRefusal
        default:
            return .none
        }
    }

    @discardableResult
    func drainOnce(at now: Date = Date()) async -> OutboxDrainResult {
        var result = OutboxDrainResult()

        let pending = (saveStore.fetchPending(durability: .localOnly) + saveStore.fetchPending(durability: .queued))
            .filter { revision in
                guard let eligible = nextEligibleAt[revision.id] else { return true }
                return eligible <= now
            }

        for revision in pending {
            let attempt: RevisionAttemptResult
            if inFlightRevisionIDs.contains(revision.id) {
                // Actors can re-enter while the first caller awaits HTTP.
                // Join that revision's outcome instead of racing a second
                // PUT/metadata commit with the same idempotency key.
                attempt = await withCheckedContinuation { continuation in
                    inFlightRevisionWaiters[revision.id, default: []].append(continuation)
                }
            } else {
                inFlightRevisionIDs.insert(revision.id)
                attempt = await upload(revision, at: now)
                inFlightRevisionIDs.remove(revision.id)
                let waiters = inFlightRevisionWaiters.removeValue(forKey: revision.id) ?? []
                waiters.forEach { $0.resume(returning: attempt) }
            }

            result.sent += attempt.sent
            if attempt.stoppedForRetry {
                result.failureClassification = attempt.failureClassification
                result.saveUploadFailureCause = attempt.saveUploadFailureCause
                result.stoppedForRetry = true
                return result
            }
        }

        return result
    }

    private func upload(_ revision: SaveRevisionRow, at now: Date) async -> RevisionAttemptResult {
        do {
            try saveStore.updateDurability(id: revision.id, durability: .queued)
            try await uploadAndCommit(revision)
            try saveStore.updateDurability(id: revision.id, durability: .uploaded)
            attemptCounts[revision.id] = nil
            nextEligibleAt[revision.id] = nil
            // A successful upload retires whatever the previous
            // attempt escalated -- the condition is demonstrably gone.
            classificationCell.set(.none)
            diagnosticEvidenceCell.set(nil)
            problemEvidenceCell.set(nil)
            return RevisionAttemptResult(
                sent: 1,
                stoppedForRetry: false,
                failureClassification: .none,
                saveUploadFailureCause: .none
            )
        } catch {
            // Left `queued` — visible and non-terminal (D-32). The pass
            // stops here so a later revision never uploads ahead of this
            // still-outstanding one.
            let classification = Self.classify(error)
            let cause = SaveUploadFailureCause.classify(error)
            classificationCell.set(classification)
            diagnosticEvidenceCell.set(Self.diagnosticEvidence(for: error))
            let problem = SaveUploadProblemEvidence(error: error)
            let diagnostic = Self.diagnosticEvidence(for: error)
            problemEvidenceCell.set(problem)
            let attempt = (attemptCounts[revision.id] ?? 0) + 1
            attemptCounts[revision.id] = attempt
            let delayAttempt = min(attempt, Outbox.maxAttempts)
            nextEligibleAt[revision.id] = now.addingTimeInterval(Outbox.retryDelay(forAttempt: delayAttempt))
            return RevisionAttemptResult(
                sent: 0,
                stoppedForRetry: true,
                failureClassification: classification,
                saveUploadFailureCause: cause
            )
        }
    }

    private func uploadAndCommit(_ revision: SaveRevisionRow) async throws {
        guard let localPath = revision.localPath else { throw SaveUploadError.missingLocalBytes }
        guard let line = saveStore.fetchLine(id: revision.saveLineID) else { throw SaveUploadError.missingLine }

        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        // A stable, persisted UUIDv7 per revision. The metadata POST uses
        // the revision ID as its Idempotency-Key and includes this command
        // ID in the body, so changing it after an uncertain response would
        // turn a safe retry into an idempotency conflict. CommandId.cast/1
        // still receives a separately generated UUIDv7 (D-20b, D-16).
        guard let commandID = try saveStore.ensureUploadCommandID(
            revisionID: revision.id, proposed: UUIDv7.generate()
        ) else { throw SaveUploadError.missingRevision }

        _ = try await apiClient.send(
            method: "PUT",
            path: "/api/v1/saves/uploads/\(commandID)",
            body: data,
            headers: [
                "Repr-Digest": Self.reprDigestHeader(for: data),
                "Content-Length": String(data.count)
            ],
            contentType: "application/octet-stream"
        )

        var params: [String: Any] = [
            "id": revision.id,
            "command_id": commandID,
            "content_key": line.contentKey,
            "save_kind": line.saveKind,
            "slot": line.slot
        ]
        if let parentRevisionID = revision.parentRevisionID { params["parent_revision_id"] = parentRevisionID }
        if let deviceCapturedAt = revision.deviceCapturedAt { params["device_captured_at"] = deviceCapturedAt }
        if let captureMethod = revision.captureMethod { params["capture_method"] = captureMethod }
        if let adapterID = revision.adapterID { params["adapter_id"] = adapterID }
        if let adapterVersion = revision.adapterVersion { params["adapter_version"] = adapterVersion }
        if let saveFormat = revision.saveFormat { params["save_format"] = saveFormat }
        if let formatConfidence = revision.formatConfidence { params["format_confidence"] = formatConfidence }
        if let playSessionID = revision.playSessionID { params["play_session_id"] = playSessionID }

        let body = try JSONSerialization.data(withJSONObject: params)

        var commitHeaders = ["Idempotency-Key": "save-revision-\(revision.id)"]
        // The isolated mac_ci reliability fixture can request one server
        // supplied 503 for this lane pass. The header is never added to a
        // normal app launch and the fixture consumes it before any effect.
        let testEnvironment = ProcessInfo.processInfo.environment
        var isTransientTestRequest = false
        if testEnvironment["PLAYSTEAD_UI_TEST_SAVE_RELIABILITY"] == "1",
           let token = testEnvironment["PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_TOKEN"],
           let transientRevisionID = testEnvironment["PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_REVISION_ID"],
           transientRevisionID.lowercased() == revision.id.lowercased(),
           UUID(uuidString: token) != nil {
            commitHeaders["X-Playstead-Test-Transient"] = token
            isTransientTestRequest = true
        }

        let response: APIResponse
        do {
            response = try await apiClient.send(
                method: "POST",
                path: "/api/v1/saves/revisions",
                body: body,
                headers: commitHeaders
            )
        } catch {
            if isTransientTestRequest, transientTestFailureEvidence == nil {
                let problem = SaveUploadProblemEvidence(error: error)
                let diagnostic = Self.diagnosticEvidence(for: error)
                transientTestFailureEvidence = (revision.id, SaveUploadFailureEvidence(
                    classification: Self.classify(error),
                    cause: SaveUploadFailureCause.classify(error),
                    status: problem?.status,
                    problemCode: problem?.code,
                    correlationID: diagnostic?.correlationID
                ))
            }
            throw error
        }

        if
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let canonicalLineID = json["save_line_id"] as? String
        {
            try? saveStore.adoptCanonicalLineID(canonicalLineID, forLocalID: revision.saveLineID)
        }

        if
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let recordedAt = json["recorded_at"] as? String
        {
            try? saveStore.setRecordedAt(id: revision.id, recordedAt: recordedAt)
        }
    }

    private static func reprDigestHeader(for data: Data) -> String {
        let raw = Data(SHA256.hash(data: data))
        return "sha-256=:\(raw.base64EncodedString()):"
    }
}
