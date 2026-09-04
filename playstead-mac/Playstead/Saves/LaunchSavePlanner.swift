import Foundation

/// One head this Mac already knows about for a save line, read from
/// already-local state only (`SaveStore.fetchHead`'s shape, flattened to
/// exactly what this planner needs — it never queries SQLite itself).
struct SaveHeadCandidate: Equatable {
    let digest: String
    /// Whether this head's revision bytes are already present in the
    /// local CAS — `false` is D-43/D-F03's "known of, not yet fetched"
    /// case, which the launch path must never fetch itself.
    let bytesLocal: Bool
    /// The device that produced this head — the one backend concept
    /// that reaches the launch-path notice copy (§9's locked strings).
    let deviceName: String
    /// Already formatted by the caller ("2 hours ago", "yesterday") —
    /// this planner never touches a clock, so relative-time rendering
    /// stays the UI layer's concern.
    let lastSavedDescription: String
}

/// Every already-local fact `LaunchSavePlanner.plan` needs: what is on
/// disk right now, every current head for this line (more than one
/// means the slot is diverged), the set of digests known to be an
/// ancestor of the single head (meaningless, and never consulted, when
/// the slot is diverged), the set of every digest this Mac has ever
/// recorded for this line, and the compatibility verdict for restoring
/// the single head onto this Mac's copy of the game (nil when there is
/// no single head to evaluate).
struct LaunchSaveContext: Equatable {
    /// `nil` when no file exists at the target path, or it exists but is
    /// zero bytes — both count as "the target is empty" (D-44).
    let onDiskDigest: String?
    let heads: [SaveHeadCandidate]
    let ancestorDigests: Set<String>
    let knownDigests: Set<String>
    let compatibilityVerdict: SaveCompatibilityGate.Verdict?

    init(
        onDiskDigest: String?,
        heads: [SaveHeadCandidate],
        ancestorDigests: Set<String> = [],
        knownDigests: Set<String> = [],
        compatibilityVerdict: SaveCompatibilityGate.Verdict? = .exact
    ) {
        self.onDiskDigest = onDiskDigest
        self.heads = heads
        self.ancestorDigests = ancestorDigests
        self.knownDigests = knownDigests
        self.compatibilityVerdict = compatibilityVerdict
    }
}

/// The exact, locked launch-path notice copy (04-CONTEXT.md's
/// "Launch-path notices" table) attached to a `SavePlan` — inline in the
/// detail view's Save section, never modal, never a toast, never the
/// card's status slot.
struct SaveLaunchNotice: Equatable {
    let title: String
    let subline: String
    let actionTitle: String?

    init(title: String, subline: String, actionTitle: String? = nil) {
        self.title = title
        self.subline = subline
        self.actionTitle = actionTitle
    }
}

/// D-44's four outcomes. `.fresh` and `.keep` both carry an *optional*
/// notice because each covers more than one case with different copy
/// (or silence): `.fresh` is silent when there is no saved progress
/// anywhere, and `.keep` is silent when the on-disk bytes are already
/// exactly the recorded head.
enum SavePlan: Equatable {
    case fresh(notice: SaveLaunchNotice?)
    case restore(revisionDigest: String, notice: SaveLaunchNotice)
    case fastForward(revisionDigest: String)
    case keep(notice: SaveLaunchNotice?)
}

/// Decides what bytes belong at `savegamePath` for one launch — pure
/// with respect to disk and network, called between
/// `LaunchMaterializer.materialize` and `AdapterHost.launch`, with the
/// impure executor (`SavePlanExecutor`) kept as a separate type.
///
/// **The governing invariant, stated verbatim as this module's
/// contract: the launch path writes save bytes only into emptiness, or
/// over bytes that hash to a proven ancestor of a single uncontested
/// head. Everything else is `.keep`.** That single testable sentence is
/// what makes silent save loss structurally impossible — a reviewer
/// should check this implementation against exactly this sentence and
/// nothing else.
///
/// Zero network calls, zero disk writes, on every path — `plan(context:)`
/// only reads the value type handed to it and returns a value type.
enum LaunchSavePlanner {
    static func plan(context: LaunchSaveContext) -> SavePlan {
        let heads = context.heads

        if let onDisk = context.onDiskDigest {
            return planWithExistingBytes(onDisk: onDisk, context: context, heads: heads)
        }
        return planIntoEmptiness(context: context, heads: heads)
    }

    // MARK: - Target already has bytes on disk

    private static func planWithExistingBytes(
        onDisk: String, context: LaunchSaveContext, heads: [SaveHeadCandidate]
    ) -> SavePlan {
        // A diverged slot never blocks Play, never prompts beforehand
        // beyond this quiet notice, and never writes the other head's
        // bytes (D-46) — checked first because ancestry is meaningless
        // to consult once more than one head exists.
        guard heads.count <= 1 else {
            return .keep(notice: Self.divergedNotice)
        }

        guard let head = heads.first else {
            // No recorded progress anywhere yet, but something is
            // already on disk — this is the "uncaptured bytes" case
            // below, handled uniformly by the shared tail.
            return keepForOnDiskBytes(onDisk, context: context)
        }

        if onDisk == head.digest {
            // Already correct — a re-run of a prior restore is a no-op.
            return .keep(notice: nil)
        }
        if context.ancestorDigests.contains(onDisk) {
            // The ONLY safe overwrite: the bytes on disk are provably a
            // proper subset of history already durable in the graph, so
            // replacing them destroys nothing (D-44).
            return .fastForward(revisionDigest: head.digest)
        }

        return keepForOnDiskBytes(onDisk, context: context)
    }

    /// The shared tail for every on-disk-bytes case that is not an exact
    /// match or a provable fast-forward: known bytes are kept silently,
    /// unrecorded bytes are kept with the "found and kept" notice — but
    /// never overwritten and never discarded.
    private static func keepForOnDiskBytes(_ onDisk: String, context: LaunchSaveContext) -> SavePlan {
        guard context.knownDigests.contains(onDisk) else {
            return .keep(notice: Self.uncapturedNotice)
        }
        return .keep(notice: nil)
    }

    // MARK: - Target is empty

    private static func planIntoEmptiness(context: LaunchSaveContext, heads: [SaveHeadCandidate]) -> SavePlan {
        guard heads.count <= 1 else {
            // Still diverged even with nothing on disk yet — writing
            // either side here would be picking a winner (D-46).
            return .keep(notice: Self.divergedNotice)
        }

        guard let head = heads.first else {
            // Genuinely nothing anywhere — starting a fresh game is the
            // normal, correct outcome (D-41), and there is nothing worth
            // saying about it.
            return .fresh(notice: nil)
        }

        guard head.bytesLocal else {
            // D-43/D-F03 makes this rare in practice (saves ride along
            // with the game download and journal-apply prefetch), but
            // the launch path must never fetch on its own — CACH-04.
            return .fresh(notice: Self.headBytesUnavailableNotice(deviceName: head.deviceName))
        }

        // Restoring INTO EMPTINESS is the one write the compatibility
        // gate must clear (D-C7/area C): only an `exact` verdict
        // silently auto-restores on the launch path. `same_title` is an
        // explicit, acknowledged action that belongs to the save
        // timeline (a later plan), never a silent launch-time write, and
        // `incompatible` never writes at all.
        guard context.compatibilityVerdict == .exact else {
            return .keep(notice: nil)
        }

        return .restore(
            revisionDigest: head.digest,
            notice: Self.restoredNotice(deviceName: head.deviceName, lastSaved: head.lastSavedDescription)
        )
    }

    // MARK: - Locked copy (04-CONTEXT.md, "Launch-path notices")

    private static func restoredNotice(deviceName: String, lastSaved: String) -> SaveLaunchNotice {
        SaveLaunchNotice(
            title: "Picked up from your \(deviceName) save.",
            subline: "Saved \(lastSaved) on \(deviceName). Nothing on this Mac was replaced."
        )
    }

    private static let uncapturedNotice = SaveLaunchNotice(
        title: "Kept the save already on this Mac.",
        subline: "Playstead found saved progress here it hadn't recorded yet, so it saved a copy before starting."
    )

    private static func headBytesUnavailableNotice(deviceName: String) -> SaveLaunchNotice {
        SaveLaunchNotice(
            title: "Starting fresh on this Mac.",
            subline: "Newer progress from \(deviceName) hasn't downloaded here yet. It's safe on your server and nothing will be overwritten.",
            actionTitle: "Download saved progress"
        )
    }

    private static let divergedNotice = SaveLaunchNotice(
        title: "Two versions of your progress.",
        subline: "Playing now continues the version on this Mac. The other version stays exactly as it is.",
        actionTitle: "Review both versions"
    )
}
