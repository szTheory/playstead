import Foundation
import CryptoKit

enum SaveUploadError: Error, Equatable {
    case missingLocalBytes
    case missingLine
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

    init(apiClient: APIClient, saveStore: SaveStore) {
        self.apiClient = apiClient
        self.saveStore = saveStore
    }

    @discardableResult
    func drainOnce() async -> OutboxDrainResult {
        var result = OutboxDrainResult()

        let pending = saveStore.fetchPending(durability: .localOnly) + saveStore.fetchPending(durability: .queued)

        for revision in pending {
            do {
                try saveStore.updateDurability(id: revision.id, durability: .queued)
                try await uploadAndCommit(revision)
                try saveStore.updateDurability(id: revision.id, durability: .uploaded)
                result.sent += 1
            } catch {
                // Left `queued` — visible and non-terminal (D-32). The
                // pass stops here so a later revision never uploads
                // ahead of this still-outstanding one.
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
        let commandID = revision.id

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
