import Foundation

/// Describes one session left open at app launch -- whatever the caller
/// (app-launch sequencing) determines needs replay. `SaveSessionRecovery`
/// never owns a dedicated "open sessions" table; `abandonedSessionIDs`
/// derives the list purely from `save_revision`'s existing tier/session
/// columns (a session with a `staged` row and no corresponding
/// `promoted` row was interrupted before its session-end promotion
/// completed), and the caller supplies the artifact source/destination
/// each abandoned session needs to actually replay.
struct AbandonedSaveSession {
    let saveLineID: String
    let sessionID: String
    let artifactSource: SaveArtifactSource
    let destinationDirectory: URL
    let artifactRelativePath: String
}

/// The crash-recovery path for "Playstead died between emulator exit and
/// capture" (D-07). At app launch, replays the **identical** settle-then-
/// promote pass a live session runs at its own end -- the same
/// `SaveCapturePoller` code path, never a reimplementation, exactly as
/// `JournalApplier`'s idempotent-by-key replay contract ("replaying a
/// page is always safe") models for the sync spine.
///
/// Idempotent by digest: a replay whose settle pass produces bytes that
/// already exist as a promoted revision for the line -- because a live
/// poller already promoted them, or because this is a second replay of
/// the same session -- inserts nothing and produces no user-visible
/// output. This is also what makes recovery safe to run concurrently
/// with a live poller finishing the same session's own promotion: only
/// the first promotion to actually land wins, and every later caller
/// (recovery included) sees its own settle-then-promote result already
/// recorded and stops there.
///
/// Never branches on `AdapterExit` -- a session with no recorded exit at
/// all is replayed exactly like one with any of the four classifications,
/// because this type never even receives an exit classification as input.
actor SaveSessionRecovery {
    private let saveStore: SaveStore

    init(saveStore: SaveStore) {
        self.saveStore = saveStore
    }

    /// Every `sessionID` for `saveLineID` that has at least one `staged`
    /// row and no `promoted` row -- "left open" by D-07's definition.
    func abandonedSessionIDs(saveLineID: String) -> [String] {
        let rows = saveStore.fetchAllRevisions().filter { $0.saveLineID == saveLineID }
        let staged = Set(rows.filter { $0.tier == SaveCaptureTier.staged.rawValue }.compactMap(\.sessionID))
        let promoted = Set(rows.filter { $0.tier == SaveCaptureTier.promoted.rawValue }.compactMap(\.sessionID))
        return staged.subtracting(promoted).sorted()
    }

    /// Replays one abandoned session: constructs a fresh
    /// `SaveCapturePoller` seeded with the line's current durable head,
    /// runs its unconditional `settle()` (D-05) followed by `promote()`
    /// (D-04) -- the exact pair a live session runs at its own end -- and
    /// persists the result only if a promoted revision with that digest
    /// does not already exist for this line. Returns the row it inserted,
    /// or `nil` when there was nothing new to promote or the digest was
    /// already recorded.
    @discardableResult
    func replay(_ session: AbandonedSaveSession, parentRevisionID: String?) async throws -> SaveRevisionRow? {
        let poller = SaveCapturePoller(
            source: session.artifactSource,
            destinationDirectory: session.destinationDirectory,
            artifactRelativePath: session.artifactRelativePath,
            sessionID: session.sessionID,
            knownHeadDigest: saveStore.fetchHead(saveLineID: session.saveLineID)?.blobSHA256
        )

        _ = try await poller.settle()
        guard let promoted = try await poller.promote() else { return nil }

        let alreadyRecorded = saveStore.fetchAllRevisions().contains {
            $0.saveLineID == session.saveLineID
                && $0.tier == SaveCaptureTier.promoted.rawValue
                && $0.blobSHA256 == promoted.sha256
        }
        guard !alreadyRecorded else { return nil }

        let row = SaveRevisionRow(
            id: UUID().uuidString,
            saveLineID: session.saveLineID,
            parentRevisionID: parentRevisionID,
            blobSHA256: promoted.sha256,
            sizeBytes: promoted.sizeBytes,
            originDeviceID: nil,
            deviceCapturedAt: nil,
            recordedAt: nil,
            captureMethod: "recovery",
            adapterID: nil,
            adapterVersion: nil,
            saveFormat: nil,
            formatConfidence: nil,
            playSessionID: session.sessionID,
            durability: SaveDurability.localOnly.rawValue,
            localPath: promoted.localPath,
            tier: promoted.tier.rawValue,
            origin: promoted.origin.rawValue,
            manifestDigest: promoted.artifactSet.manifestDigest,
            sessionID: session.sessionID,
            artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
        return row
    }

    /// Replays every abandoned session for `saveLineID` in one pass --
    /// the shape app launch calls once per known save line.
    @discardableResult
    func replayAll(saveLineID: String, artifactSource: SaveArtifactSource, destinationDirectory: URL, artifactRelativePath: String) async throws -> [SaveRevisionRow] {
        var results: [SaveRevisionRow] = []
        for sessionID in abandonedSessionIDs(saveLineID: saveLineID) {
            let head = saveStore.fetchHead(saveLineID: saveLineID)
            let session = AbandonedSaveSession(
                saveLineID: saveLineID, sessionID: sessionID, artifactSource: artifactSource,
                destinationDirectory: destinationDirectory, artifactRelativePath: artifactRelativePath
            )
            if let row = try await replay(session, parentRevisionID: head?.id) {
                results.append(row)
            }
        }
        return results
    }
}
