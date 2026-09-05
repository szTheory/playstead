import Foundation

/// The two path rules the capture pipeline shares with the launch
/// (restore) pipeline, stated once so the two halves can never drift.
///
/// Before this existed, `GameRowView.buildSaveLaunchPlan` spelled the
/// `{saveDir}/{romBaseName}.sav` rule out inline and nothing else knew
/// it. The capture half and the crash-recovery half both need the exact
/// same artifact path -- a second, independently-derived spelling of it
/// is precisely how "the app captures a file nobody restores" happens.
enum SaveCapturePaths {
    /// The save contract's artifact path for one launch:
    /// `{saveDir}/{romBaseName}.sav` (`SavePlanExecutor`'s own doc
    /// comment), where `romBaseName` is the ROM filename with its
    /// extension stripped.
    static func targetURL(saveDirectory: URL, romFileName: String) -> URL {
        let base = URL(fileURLWithPath: romFileName).deletingPathExtension().lastPathComponent
        return saveDirectory.appendingPathComponent("\(base).sav")
    }

    /// Where a session's durable captures land. Deliberately NOT the
    /// save directory itself: the adapter's `artifact_glob` owns that
    /// directory, and dropping `<digest>.sav` blobs beside the live
    /// artifact would put Playstead's own bookkeeping inside the
    /// emulator's declared workspace.
    ///
    /// The asset set id is server-supplied, so it is validated as a
    /// safe bare filename before it becomes a path component, exactly
    /// as `AppEnvironment.saveDirectoryURL(forAssetSetID:)` does
    /// (CR-01/CR-02).
    static func captureDirectory(root: URL, assetSetID: String) throws -> URL {
        let safe = try PathSafety.validatedFilename(assetSetID)
        return root
            .appendingPathComponent("save-captures", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }
}

/// One play session's capture lifecycle, bound to one save line and one
/// on-disk artifact, and nothing else.
///
/// This type exists because `GameRowView.play()` is a private
/// `@MainActor` SwiftUI method no test can drive: putting the capture
/// lifecycle inline there would reproduce, on the capture half, exactly
/// the WINDOWS #37 defect that `buildSaveLaunchPlan` was extracted to
/// fix on the restore half. `play()` calls `begin()`/`end()` on this
/// type; tests construct the same type and drive the same two methods.
///
/// It **owns no capture logic**. Quiescence detection, digest
/// comparison, the durable write order, settle and promote all live in
/// `SaveCapturePoller` and are called, never reimplemented -- a second
/// settle-then-promote implementation is the exact mistake
/// `SaveSessionRecovery`'s own doc comment warns against. What this type
/// adds is only the three things the poller deliberately does not do:
/// read the line's current head from `SaveStore` before construction,
/// insert the `save_revision` rows the poller's captures correspond to,
/// and route a capture failure into `SaveCaptureBlockedState` (D-31)
/// instead of letting it surface as "Launch failed".
actor SaveSessionCoordinator {
    private let saveStore: SaveStore
    private let blockedState: SaveCaptureBlockedState?
    private let pollInterval: TimeInterval
    /// Fired after a promoted revision is durably recorded, so the
    /// upload lane drains it without this type knowing the lane exists.
    private let onPromoted: (@Sendable () -> Void)?

    /// Non-nil exactly while a session is open. `end()` clears it, which
    /// is what makes a second `end()` -- or an `end()` with no `begin()`
    /// -- a no-op rather than a crash or a duplicate promotion.
    private var poller: SaveCapturePoller?
    private var openSaveLineID: String?
    /// The revision the session's promotion parents onto: the baseline
    /// row if `startSession()` created one (that row IS the head by the
    /// time the session ends), otherwise the head read at `begin()`.
    private var parentRevisionID: String?

    init(
        saveStore: SaveStore,
        blockedState: SaveCaptureBlockedState? = nil,
        pollInterval: TimeInterval = 1.0,
        onPromoted: (@Sendable () -> Void)? = nil
    ) {
        self.saveStore = saveStore
        self.blockedState = blockedState
        self.pollInterval = pollInterval
        self.onPromoted = onPromoted
    }

    /// True exactly while a session is open -- the property a test
    /// asserts against instead of reaching into the poller.
    var isSessionOpen: Bool { poller != nil }

    /// The session id the open session's captures carry, or `nil`.
    /// `SaveCapturePoller.sessionID` is an immutable `let`, so reading it
    /// crosses no actor boundary.
    var openSessionID: String? { poller?.sessionID }

    /// Opens a capture session for `saveLineID` over the artifact at
    /// `targetURL`.
    ///
    /// Runs D-04's session-start baseline check first: the poller is
    /// seeded with the line's current head digest, and `startSession()`
    /// returns a `baseline` capture only when the bytes already on disk
    /// differ from it -- an out-of-band change made outside Playstead,
    /// which must be recorded before the session's own writes bury it.
    /// Then starts the 1 Hz poll loop (D-01).
    ///
    /// Never throws: a capture that cannot be written is recorded as a
    /// blockage (D-31) and the game still launches.
    func begin(
        saveLineID: String,
        targetURL: URL,
        destinationDirectory: URL,
        artifactRelativePath: String
    ) async {
        guard poller == nil else { return }

        let head = saveStore.fetchHead(saveLineID: saveLineID)
        let poller = SaveCapturePoller(
            source: FileSaveArtifactSource(url: targetURL),
            destinationDirectory: destinationDirectory,
            pollInterval: pollInterval,
            artifactRelativePath: artifactRelativePath,
            knownHeadDigest: head?.blobSHA256
        )
        self.poller = poller
        self.openSaveLineID = saveLineID
        self.parentRevisionID = head?.id

        do {
            if let baseline = try await poller.startSession() {
                let row = try persist(
                    baseline, saveLineID: saveLineID, parentRevisionID: head?.id, captureMethod: "baseline"
                )
                // The baseline row is now this line's head, so the
                // session's own promotion parents onto it rather than
                // onto the pre-baseline head it superseded.
                self.parentRevisionID = row.id
                await clearBlockage(saveLineID: saveLineID)
            }
        } catch {
            await recordBlockage(
                saveLineID: saveLineID, sessionID: poller.sessionID, digest: nil, error: error
            )
        }

        await poller.start()
    }

    /// Closes the session: D-05's unconditional `settle()` pass followed
    /// by D-04's `promote()`, in that order and never branching on how
    /// the session ended, then records the promoted capture as a
    /// `localOnly` revision and stops the poll loop.
    ///
    /// Safe to call when `begin()` never ran or already ended, and never
    /// throws out to its caller: a failed capture must never surface to
    /// the user as a failed launch. A failure is recorded as a blockage
    /// (D-31) so it is visible rather than silent.
    func end() async {
        guard let poller, let saveLineID = openSaveLineID else { return }
        self.poller = nil
        self.openSaveLineID = nil
        let parent = parentRevisionID
        self.parentRevisionID = nil

        // `stop()` first, then `settle()`, then `promote()` -- the exact
        // order `SaveCapturePoller.start()`'s own doc comment specifies
        // ("Stopped by `stop()` at session end, immediately followed by
        // `settle()` and `promote()`"), so no 1 Hz `observe()` can land a
        // staged capture between the settle pass and the promotion it
        // feeds.
        await poller.stop()

        do {
            _ = try await poller.settle()
            if let promoted = try await poller.promote() {
                _ = try persist(
                    promoted, saveLineID: saveLineID, parentRevisionID: parent, captureMethod: "session"
                )
                onPromoted?()
            }
            await clearBlockage(saveLineID: saveLineID)
        } catch {
            await recordBlockage(
                saveLineID: saveLineID, sessionID: poller.sessionID, digest: nil, error: error
            )
        }
    }

    // MARK: - Persistence

    /// Records one capture as a `save_revision` row. Field-for-field the
    /// same construction `SaveSessionRecovery.replay` performs -- the two
    /// paths write the same shape of row because they capture the same
    /// way -- differing only in `captureMethod`, which is the one thing
    /// that genuinely differs between a live session, its session-start
    /// baseline, and a crash replay.
    @discardableResult
    private func persist(
        _ capture: CapturedSave, saveLineID: String, parentRevisionID: String?, captureMethod: String
    ) throws -> SaveRevisionRow {
        let row = SaveRevisionRow(
            id: UUID().uuidString,
            saveLineID: saveLineID,
            parentRevisionID: parentRevisionID,
            blobSHA256: capture.sha256,
            sizeBytes: capture.sizeBytes,
            originDeviceID: nil,
            deviceCapturedAt: nil,
            recordedAt: nil,
            captureMethod: captureMethod,
            adapterID: nil,
            adapterVersion: nil,
            saveFormat: nil,
            formatConfidence: nil,
            playSessionID: capture.sessionID,
            durability: SaveDurability.localOnly.rawValue,
            localPath: capture.localPath,
            tier: capture.tier.rawValue,
            origin: capture.origin.rawValue,
            manifestDigest: capture.artifactSet.manifestDigest,
            sessionID: capture.sessionID,
            artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
        return row
    }

    // MARK: - Blockage (D-31)

    private func recordBlockage(saveLineID: String, sessionID: String, digest: String?, error: Error) async {
        guard let blockedState else { return }
        _ = try? await blockedState.recordFailure(
            saveLineID: saveLineID, sessionID: sessionID, digest: digest, reason: "\(error)"
        )
    }

    private func clearBlockage(saveLineID: String) async {
        guard let blockedState else { return }
        try? await blockedState.clearBlockage(saveLineID: saveLineID)
    }
}

/// One launch's resolved capture wiring: the coordinator, the line it is
/// bound to, and the exact artifact path and capture directory it will
/// use. Returned by `GameRowView.buildSaveCaptureCoordinator` so a test
/// can assert the binding -- most importantly that `targetURL` is the
/// same path the launch save plan writes to -- without driving
/// `play()`'s SwiftUI machinery.
struct SaveCaptureWiring {
    let coordinator: SaveSessionCoordinator
    let saveLineID: String
    let targetURL: URL
    let destinationDirectory: URL
    let artifactRelativePath: String

    func begin() async {
        await coordinator.begin(
            saveLineID: saveLineID,
            targetURL: targetURL,
            destinationDirectory: destinationDirectory,
            artifactRelativePath: artifactRelativePath
        )
    }

    func end() async {
        await coordinator.end()
    }
}
