import Foundation

/// One side's title-identity reading from Phase 2's
/// `Playstead.Recognition.ReferenceMatch` — the only machinery in this
/// codebase that can say "these two different byte streams are the same
/// game" (D-22). Only `.matched` with `.exact` confidence, on **both**
/// sides against the **same** title group, ever widens a restore across
/// a `romSHA256` mismatch; `.variant`, `.noMatch`, or an absent reading
/// never widens — the gate degrades toward strictness when identity is
/// unknown.
struct SaveTitleIdentity: Equatable {
    enum MatchStatus: String, Equatable {
        case matched
        case variant
        case noMatch
    }

    enum Confidence: String, Equatable {
        case exact
        case approximate
    }

    let status: MatchStatus
    let confidence: Confidence
    /// The DAT/reference title-group both sides must agree on — being
    /// independently `.matched(.exact)` against two unrelated titles
    /// must never widen the gate.
    let titleGroupID: String

    var isCertainMatch: Bool { status == .matched && confidence == .exact }
}

/// Provenance only — recorded for SEED-001, never read by
/// `SaveCompatibilityGate.evaluate`. A GBA battery save is written by
/// the game's own code, not the emulator, so gating on any of these
/// fields would be save-*state* thinking misapplied to a system save
/// (D-18).
struct SaveProvenance: Equatable {
    let emulator: String
    let emulatorVersion: String
    let coreVersion: String?
    let adapterPinSHA256: String
    let capturedAt: String
    let deviceID: String
}

/// The binding tuple denormalized onto a save revision's payload at
/// capture time (D-18, D-22) — every field the gate reads is already
/// local; evaluating a verdict never requires a network call or a CAS
/// lookup.
struct SaveBinding: Equatable {
    let systemID: String
    /// `"battery"` in Phase 4 — a mismatch here is a hard block; see
    /// `SaveCompatibilityGate.evaluate`.
    let saveKind: String
    /// `nil` when the observed artifact byte count did not match any
    /// medium the adapter pin declares — an *unbound* revision, never
    /// restorable regardless of every other field.
    let mediumID: String?
    let artifactBytes: Int
    let romSHA256: String
    let titleIdentity: SaveTitleIdentity?
    /// `"emulated"` in Phase 4 — SEED-002's door, recorded but never
    /// gated on.
    let origin: String
    let provenance: SaveProvenance
}

/// Pure evaluator, mirroring `ReadinessEngine`'s zero-network, disk-free
/// shape: struct in, verdict out. Owns zero dependency on the CAS, the
/// network, or the emulator process — the adapter's `save_contract` is
/// data this type reads, not a collaborator.
struct SaveCompatibilityGate {
    enum Verdict: Equatable {
        case exact
        /// A cross-line restore permitted only by a certain title match
        /// on both sides (D-19's arbitration: `same_title` creates a
        /// child revision on the target line, since lines are keyed on
        /// ROM sha256 and a different dump is a different line).
        case sameTitle
        /// A hard block with no override affordance of any kind (D-20).
        case incompatible(reason: String)
    }

    /// The adapter's declared save contract — read for its
    /// `provenMedia`/`maxArtifactBytes` bounds only; `binding_fields`
    /// vs `provenance_fields` is the seam a future save-state adapter
    /// entry widens without a client change (SEED-019), and this type's
    /// own field selection below already matches D-18's binding tuple.
    let saveContract: AdapterSaveContract

    /// Evaluates whether `candidate` (a save revision under
    /// consideration for restore) may be written onto `target` (the
    /// binding this Mac's own copy of the game currently expects).
    /// Zero network calls, zero disk I/O, zero side effects on every
    /// path.
    func evaluate(candidate: SaveBinding, target: SaveBinding) -> Verdict {
        guard candidate.systemID == target.systemID else {
            return .incompatible(reason: "different_system")
        }
        guard candidate.saveKind == target.saveKind else {
            return .incompatible(reason: "different_save_kind")
        }

        // The destructive case (D-20): GBA's backup media share the
        // same memory-map space through incompatible interfaces, so a
        // mismatched write is the documented path to the game itself
        // declaring the save corrupt and offering to erase it. Hard
        // block, no override, ever — including an unbound (`nil`)
        // medium on either side.
        guard let candidateMedium = candidate.mediumID, let targetMedium = target.mediumID,
              candidateMedium == targetMedium
        else {
            return .incompatible(reason: "medium_mismatch")
        }
        guard candidate.artifactBytes == target.artifactBytes else {
            return .incompatible(reason: "artifact_bytes_mismatch")
        }

        if candidate.romSHA256 == target.romSHA256 {
            return .exact
        }

        // Widening requires a certain, matching title-group reading on
        // BOTH sides (D-22) — never a filename or title-string
        // heuristic, and never promoted by a `:variant`/`:no_match`/
        // absent reading on either side.
        guard let candidateIdentity = candidate.titleIdentity, candidateIdentity.isCertainMatch,
              let targetIdentity = target.titleIdentity, targetIdentity.isCertainMatch,
              candidateIdentity.titleGroupID == targetIdentity.titleGroupID
        else {
            return .incompatible(reason: "no_certain_title_match")
        }

        return .sameTitle
    }
}
