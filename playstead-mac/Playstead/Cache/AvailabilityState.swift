import Foundation

/// The four facts `AvailabilityState.derive(_:)` reads from disk/store to
/// compute a game's availability at render time. Deliberately NOT stored
/// as any kind of cached/memoized state on this type — every call site
/// (`GameCardView`, `StorageView`, a database-rebuild test) re-derives
/// from these four facts fresh, per D-21: a stored state column drifts
/// from disk the first moment a file is removed, restored, or corrupted
/// outside the app, and a user who sees "verified" over content that
/// isn't there loses the only thing this product is selling.
struct AvailabilityInputs: Equatable {
    /// Every member (`sha256`) the game's manifest marks `required`.
    /// A game with an empty required-member set is a manifest defect
    /// upstream of this type; `derive` treats it as `.serverOnly` rather
    /// than vacuously "verified," since "every required member cached"
    /// over zero members is not a claim worth making.
    let requiredMemberSHAs: [String]

    /// Members that currently have a `download_queue_items` row, in ANY
    /// transfer state (waiting, active, paused) — cancelled rows are
    /// excluded by the caller before this struct is built, since a
    /// cancelled item is no longer "in the queue" for availability
    /// purposes.
    let queuedMemberSHAs: Set<String>

    /// The one member (if any) whose queue row is currently `active` —
    /// `DownloadCoordinator` drives exactly one transfer at a time.
    let activeMemberSHA: String?

    /// 0...100, the active member's current transfer progress. `nil`
    /// when `activeMemberSHA` is `nil` or progress isn't yet known.
    let activeMemberProgressPercent: Int?

    /// Members present in the content-addressed cache (`CASManager`/
    /// `cache_objects`) — i.e. fully committed and verified, not merely
    /// partially downloaded.
    let cachedMemberSHAs: Set<String>

    /// Whether the user has pinned this game (`PinStore`). Pin implies
    /// the content is already fully cached (D-21) — a pinned-but-not-
    /// fully-cached input combination is a caller defect, and `derive`
    /// resolves it conservatively by NOT reporting `.pinnedOffline` until
    /// every required member is actually present (see inline comment).
    let isPinned: Bool

    init(
        requiredMemberSHAs: [String],
        queuedMemberSHAs: Set<String> = [],
        activeMemberSHA: String? = nil,
        activeMemberProgressPercent: Int? = nil,
        cachedMemberSHAs: Set<String> = [],
        isPinned: Bool = false
    ) {
        self.requiredMemberSHAs = requiredMemberSHAs
        self.queuedMemberSHAs = queuedMemberSHAs
        self.activeMemberSHA = activeMemberSHA
        self.activeMemberProgressPercent = activeMemberProgressPercent
        self.cachedMemberSHAs = cachedMemberSHAs
        self.isPinned = isPinned
    }
}

/// One of the six availability states this phase's custody promise
/// depends on (D-21). Deliberately NOT a stored column anywhere in
/// `Migrations.swift` — see `AvailabilityInputs`'s doc comment.
///
/// `.safeToEvict` is meaningful only in the storage view's context (it
/// additionally requires "unpinned," which `derive` alone cannot decide
/// without also consulting `PinStore` — see `deriveForStorageView(_:)`
/// below). The plain `derive(_:)` entry point a card uses NEVER returns
/// `.safeToEvict`.
enum AvailabilityState: Equatable {
    case serverOnly
    case queued
    case partial
    case verifiedLocal
    case pinnedOffline
    case safeToEvict

    /// The read-time derivation every card, list row, and rebuild-from-
    /// disk test calls. Pure — no I/O, no caching, no memoized state.
    static func derive(_ inputs: AvailabilityInputs) -> AvailabilityState {
        let required = inputs.requiredMemberSHAs
        guard !required.isEmpty else { return .serverOnly }

        let allCached = required.allSatisfy { inputs.cachedMemberSHAs.contains($0) }
        if allCached {
            // Pin implies verified (D-21) — a pinned game is always fully
            // cached by the time it can be pinned, so this branch is the
            // only place `.pinnedOffline` is ever returned.
            return inputs.isPinned ? .pinnedOffline : .verifiedLocal
        }

        let anyCached = required.contains { inputs.cachedMemberSHAs.contains($0) }
        if anyCached {
            return .partial
        }

        // No member is cached yet, but at least one has a queue row: "a
        // game with queue rows and no bytes derives as queued" — this is
        // the ONLY branch that returns `.queued`; the moment any byte is
        // cached, the state above (`anyCached`) already claimed `.partial`.
        let anyQueued = required.contains { inputs.queuedMemberSHAs.contains($0) }
        if anyQueued {
            return .queued
        }

        return .serverOnly
    }

    /// The storage-view-only entry point: `.safeToEvict` additionally
    /// requires the game be unpinned. Never called by `GameCardView` —
    /// the card asks for the badge-eligible subset via `derive(_:)` and
    /// never receives `.safeToEvict`, by construction (there is no path
    /// from `derive(_:)` to this case).
    static func deriveForStorageView(_ inputs: AvailabilityInputs) -> AvailabilityState {
        let base = derive(inputs)
        if base == .verifiedLocal, !inputs.isPinned {
            return .safeToEvict
        }
        return base
    }
}
