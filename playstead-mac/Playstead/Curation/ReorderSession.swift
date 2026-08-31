import Foundation

/// The shared "preview many moves, commit exactly one intent" reorder
/// discipline used by every curation surface that lets a user
/// drag-reorder a list: snapshot the current order, mutate an in-memory
/// preview as the drag gesture updates, then settle the gesture into the
/// moved row's final before/after neighbours and a single computed
/// `FractionalPosition`. Previously implemented twice, nearly verbatim,
/// in `CollectionsViewModel` and `QueueViewModel` — this type exists so
/// the ordering math (and any future fix to it, such as a
/// `needsRebalance` pre-check) lives in exactly one place.
///
/// One instance is scoped to a single reorderable list (one collection's
/// members, or the one queue). `CollectionsViewModel` keeps a dictionary
/// of these keyed by collection id; `QueueViewModel` keeps exactly one.
final class ReorderSession {
    /// The result of settling a drag gesture: the moved row's computed
    /// final position and its (possibly nil, at either end) neighbours.
    struct Move {
        let position: String
        let beforeID: String?
        let afterID: String?
    }

    private var previewOrder: [String]?

    /// Snapshots the list's current order (row identifiers, in position
    /// order) into an in-memory preview — call once when a drag gesture
    /// begins.
    func begin(order: [String]) {
        previewOrder = order
    }

    /// Mutates only the in-memory preview order — call as many times as
    /// the drag gesture updates (no outbox write, no network, no
    /// intermediate position ever computed here).
    func previewMove(id: String, to index: Int) {
        guard var order = previewOrder else { return }
        order.removeAll { $0 == id }
        let clamped = max(0, min(index, order.count))
        order.insert(id, at: clamped)
        previewOrder = order
    }

    /// Settles the drag gesture: computes `id`'s final neighbours from
    /// the in-memory preview order and, via the caller-supplied
    /// `positionOf` lookup (queried fresh, not cached, so a caller like
    /// `CollectionsViewModel` that re-fetches at commit time gets
    /// current positions), the single `FractionalPosition` to enqueue.
    /// Always clears the in-progress preview, whether or not a move is
    /// returned, matching the "exactly one intent per gesture, then
    /// reset" contract every caller relies on.
    func commit(id: String, positionOf: (String) -> String?) -> Move? {
        defer { previewOrder = nil }
        guard let order = previewOrder, let movedIndex = order.firstIndex(of: id) else { return nil }

        let beforeID = movedIndex > 0 ? order[movedIndex - 1] : nil
        let afterID = movedIndex < order.count - 1 ? order[movedIndex + 1] : nil
        let beforePosition = beforeID.flatMap(positionOf)
        let afterPosition = afterID.flatMap(positionOf)
        let position = FractionalPosition.between(beforePosition, afterPosition)

        return Move(position: position, beforeID: beforeID, afterID: afterID)
    }
}
