import Foundation

/// Which emulator build produced a capture.
///
/// `save_revision.adapter_id` / `adapter_version` exist client-side
/// (`SaveStore`), on the wire (`SaveUploadLane` forwards both when
/// present) and server-side (`Playstead.Saves`, `SavePayload`) -- and
/// until this type existed every one of those was fed a literal `nil`
/// by both production writers, so every revision the shipped app ever
/// produced said `''` (WINDOWS #57). The columns were plumbed end to
/// end and nothing filled them.
///
/// This type is the single place that answers "which adapter", so the
/// live-session writer (`SaveSessionCoordinator.persist`) and the
/// crash-replay writer (`SaveSessionRecovery.replay`) cannot record
/// different provenance for two captures of the same artifact. Both
/// take it as a **required** initializer parameter, deliberately with
/// no default: a default is what let the `nil` sit unnoticed, and the
/// compiler refusing to build a writer that does not name its
/// provenance is a stronger guarantee than any test.
///
/// The pin is the honest source. `AdapterInstaller` records exactly one
/// installation row per `(pin.emulator, pin.version)` and verifies the
/// downloaded archive's digest against `AdapterPin.sha256` before
/// trusting it, so the installed build *is* the pinned build -- and a
/// user-selected build is recorded under the same pin identity with
/// `provenance == .userSelected`, which is a separate fact this type
/// does not restate.
struct SaveCaptureProvenance: Equatable, Sendable {
    /// The emulator's id, e.g. `"mgba"` -- the same string
    /// `LaunchSaveContextBuilder` reads back as `emulator` when it
    /// builds a launch context from the line's head revision.
    let adapterID: String?
    /// The pinned emulator release, e.g. `"0.10.5"`.
    let adapterVersion: String?

    init(adapterID: String?, adapterVersion: String?) {
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
    }

    init(pin: AdapterPin) {
        self.init(adapterID: pin.emulator, adapterVersion: pin.version)
    }

    /// No pin could be loaded, so the app genuinely does not know which
    /// adapter is in play. Recorded as absent rather than guessed: a
    /// fabricated `"mgba"` on a build whose pin failed to decode would
    /// be worse than an empty column, because it would be believed.
    static let unknown = SaveCaptureProvenance(adapterID: nil, adapterVersion: nil)
}
