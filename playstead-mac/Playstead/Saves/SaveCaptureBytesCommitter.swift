import Foundation

/// Puts one capture's bytes into the CAS -- the exact staging-copy,
/// already-present-no-op, and staged-cleanup-on-throw behaviour
/// `SaveSessionCoordinator.commitCaptureBytes` originally implemented,
/// extracted so `SaveSessionRecovery`'s crash-recovery path shares it
/// instead of re-deriving a second implementation (WINDOWS #52). Two
/// implementations of a content-addressed commit is how the live and
/// recovery paths drifted apart in the first place: the live path always
/// committed a promoted capture's bytes into the CAS, and the recovery
/// path never did.
struct SaveCaptureBytesCommitter {
    let casManager: CASManager

    init(casManager: CASManager) {
        self.casManager = casManager
    }

    /// Returns the failure rather than throwing it -- a capture whose
    /// bytes are durably on disk but not in the CAS is a degraded
    /// history/restore state, not lost data: the caller still has the
    /// row's `localPath` to fall back on (that is where `SaveUploadLane`
    /// reads bytes from). Aborting a revision-row insert on a CAS
    /// failure would turn a durability *improvement* into save loss, so
    /// every caller records the row regardless and surfaces the failure
    /// as a D-31 blockage instead.
    func commit(_ capture: CapturedSave) -> Error? {
        // A digest already in the CAS is a no-op, not an error -- the
        // same bytes legitimately arrive twice (a replayed session, a
        // byte-identical capture, or a recovery replay racing a live
        // session's own promotion of the same digest). Content-addressing
        // makes the two copies identical by construction.
        guard !casManager.contains(capture.sha256) else { return nil }

        do {
            // `CASManager.commit` *moves* its source into `objects/`, and
            // `capture.localPath` is the permanent capture artifact the
            // revision row points at. So a copy is staged under
            // `partials/` and that copy is what gets moved -- the
            // capture itself is never consumed.
            let source = URL(fileURLWithPath: capture.localPath)
            let staged = try casManager.paths
                .partialURL(for: capture.sha256)
                .appendingPathExtension("save-stage")
            let fm = FileManager.default
            try fm.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: source, to: staged)
            do {
                try casManager.commit(partialAt: staged, sha256: capture.sha256)
            } catch {
                // A failed commit must not leave the staging copy behind
                // as a permanent orphan under `partials/`.
                try? fm.removeItem(at: staged)
                throw error
            }
            return nil
        } catch {
            return error
        }
    }
}
