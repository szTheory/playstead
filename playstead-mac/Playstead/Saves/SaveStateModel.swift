import Foundation

/// D-35: three orthogonal axes describing where a save revision stands --
/// durability, position (`current`), and provenance (`restored`) -- plus
/// `conflicted`, a property of a *set* of revisions (a line's current
/// heads), never a fourth per-revision field. A revision can be truthfully
/// uploaded, current on this device, AND restored here all at once.
///
/// There is deliberately no single collapsing function anywhere that
/// takes a game and returns one combined save-status enum. Collapsing
/// these axes into one enum is a bug, not a simplification -- the whole
/// point of D-35 is that a save's state is several independent facts,
/// not one label.
enum SaveStateModel {
    /// `current` is a property of a *(revision, device)* pair, never of a
    /// revision alone -- the same revision can be current on one device
    /// and not current on another.
    struct CurrentPosition: Equatable, Hashable {
        let revisionID: String
        let deviceID: String
    }

    /// One revision's full, truthful reading across all three axes at
    /// once. `isCurrent` and `isRestoredHere` are independent booleans,
    /// never branches of a shared enum with `durability`.
    struct RevisionState: Equatable {
        let revisionID: String
        let durability: SaveDurability
        let isCurrent: Bool
        let isRestoredHere: Bool
    }

    /// Durability only ever moves forward -- `localOnly` -> `queued` ->
    /// `uploaded` -- never back. A revision already `uploaded` can never
    /// be observed transitioning to `queued` or `localOnly`.
    static func isValidDurabilityTransition(from current: SaveDurability, to next: SaveDurability) -> Bool {
        rank(next) >= rank(current)
    }

    private static func rank(_ durability: SaveDurability) -> Int {
        switch durability {
        case .localOnly: return 0
        case .queued: return 1
        case .uploaded: return 2
        }
    }

    /// Provenance is immutable once set: a revision that has been marked
    /// restored here stays restored here forever. There is no legal
    /// transition from `true` back to `false`.
    static func isValidRestoredTransition(from current: Bool, to next: Bool) -> Bool {
        !current || next
    }

    /// D-35/D-38: `conflicted` is derived from a *set* of revisions --
    /// the line's current heads -- never stored as a per-revision field.
    /// More than one head means the line has diverged; this is the only
    /// place "conflicted" is computed anywhere in this codebase.
    static func isConflicted<C: Collection>(headRevisionIDs: C) -> Bool where C.Element == String {
        Set(headRevisionIDs).count > 1
    }
}
