import Foundation
import CryptoKit

enum SaveUploadError: Error, Equatable {
    case missingLocalBytes
    case missingLine
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

/// Drains locally-captured save revisions to the server: a streamed
/// upload, then the idempotent metadata commit, in that order, for one
/// revision at a time (D-16, D-32). A dedicated lane — not a priority
/// band inside the curation `OutboxWorker` — so it is drained ahead of
/// the curation outbox and downloads regardless of what else is
/// queued, per D-32.
///
/// Reuses `OutboxWorker`'s actor-serialized, in-order, stop-on-retry
/// drain shape: two concurrent `drainOnce()` calls racing the same
/// revision could otherwise upload it twice concurrently before either
/// transitions its local `durability` state. A revision that fails
/// never reaches a silent terminal state (D-32) — it stays `queued`
/// (visible, never quarantined-to-silence) and is retried on the next
/// `drainOnce()` call.
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

    private let classificationCell = SaveUploadClassificationCell()

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
            do {
                try saveStore.updateDurability(id: revision.id, durability: .queued)
                try await uploadAndCommit(revision)
                try saveStore.updateDurability(id: revision.id, durability: .uploaded)
                attemptCounts[revision.id] = nil
                nextEligibleAt[revision.id] = nil
                // A successful upload retires whatever the previous
                // attempt escalated -- the condition is demonstrably
                // gone.
                classificationCell.set(.none)
                result.sent += 1
            } catch {
                // Left `queued` — visible and non-terminal (D-32). The
                // pass stops here so a later revision never uploads
                // ahead of this still-outstanding one.
                classificationCell.set(Self.classify(error))
                let attempt = (attemptCounts[revision.id] ?? 0) + 1
                attemptCounts[revision.id] = attempt
                let delayAttempt = min(attempt, Outbox.maxAttempts)
                nextEligibleAt[revision.id] = now.addingTimeInterval(Outbox.retryDelay(forAttempt: delayAttempt))
                result.stoppedForRetry = true
                return result
            }
        }

        return result
    }

    private func uploadAndCommit(_ revision: SaveRevisionRow) async throws {
        guard let localPath = revision.localPath else { throw SaveUploadError.missingLocalBytes }
        guard let line = saveStore.fetchLine(id: revision.saveLineID) else { throw SaveUploadError.missingLine }

        let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
        // A fresh UUIDv7 per attempt — never `revision.id`, whose format
        // this lane does not control, and `CommandId.cast/1` requires
        // UUIDv7 specifically (D-20b, D-16).
        let commandID = UUIDv7.generate()

        _ = try await apiClient.send(
            method: "PUT",
            path: "saves/uploads/\(commandID)",
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

        let response = try await apiClient.send(
            method: "POST",
            path: "saves/revisions",
            body: body,
            headers: ["Idempotency-Key": "save-revision-\(revision.id)"]
        )

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
