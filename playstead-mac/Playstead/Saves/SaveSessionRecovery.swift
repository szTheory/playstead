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
/// Never branches on how the session's process exited -- a session with
/// no recorded exit classification at all is replayed exactly like one
/// with any exit classification, because this type never even receives
/// one as input.
actor SaveSessionRecovery {
    private let saveStore: SaveStore
    /// Commits a replayed promotion's bytes into the CAS before its row
    /// is inserted -- the same ordering `SaveSessionCoordinator`
    /// establishes for the live path, now shared rather than absent
    /// here (WINDOWS #52). Before this, a session recovered from a
    /// crash left `LaunchSaveContextBuilder.bytesLocal` reporting
    /// `false` for it -- a crash-recovered capture was never as durable
    /// as a live one.
    private let bytesCommitter: SaveCaptureBytesCommitter
    private let blockedState: SaveCaptureBlockedState?
    /// The same required, undefaulted provenance the live path takes
    /// (`SaveSessionCoordinator`). A crash-replayed capture came off the
    /// same emulator as the session it replays, so recording it as
    /// unknown here -- or worse, recording something different -- would
    /// make provenance depend on whether the emulator happened to exit
    /// cleanly.
    private let provenance: SaveCaptureProvenance

    init(
        saveStore: SaveStore,
        casManager: CASManager,
        blockedState: SaveCaptureBlockedState? = nil,
        provenance: SaveCaptureProvenance
    ) {
        self.saveStore = saveStore
        self.bytesCommitter = SaveCaptureBytesCommitter(casManager: casManager)
        self.blockedState = blockedState
        self.provenance = provenance
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

        // CAS first, then the row that names the digest -- the same
        // ordering the live path establishes, so a reader never observes
        // a recovered revision row pointing at bytes the CAS does not
        // have. A commit failure is recorded as a D-31 blockage and does
        // NOT abort the insert: the row's `localPath` is still where
        // `SaveUploadLane` reads bytes from, so dropping the row would
        // turn a durability improvement into save loss.
        let casFailure = bytesCommitter.commit(promoted)

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
            adapterID: provenance.adapterID,
            adapterVersion: provenance.adapterVersion,
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
        if let casFailure {
            await recordBlockage(
                saveLineID: session.saveLineID, sessionID: session.sessionID, digest: promoted.sha256, error: casFailure
            )
        }
        return row
    }

    // MARK: - Blockage (D-31)

    private func recordBlockage(saveLineID: String, sessionID: String, digest: String?, error: Error) async {
        guard let blockedState else { return }
        _ = try? await blockedState.recordFailure(
            saveLineID: saveLineID, sessionID: sessionID, digest: digest, reason: "\(error)"
        )
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
