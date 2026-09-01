import Foundation

/// Collections: create/rename/delete, and member add/remove/reorder, all
/// offline-first over `Outbox` (plan 03-08 task 2). Positions are
/// computed locally with `FractionalPosition` so an add or reorder is
/// immediate; the server always recomputes the settled position from
/// the named neighbours, which then arrives through the journal.
@Observable
final class CollectionsViewModel {
    private let curationStore: CurationStore
    private let outbox: Outbox

    private(set) var collections: [CurationCollectionRow] = []
    /// Invalidates views whose member rows are read directly from SQLite.
    /// `collections` alone cannot provide that dependency because collection
    /// metadata does not change when an optimistic member move settles.
    private(set) var memberRevision = 0
    /// One `ReorderSession` per collection currently mid-drag — never
    /// written to the outbox until `commitReorderMembers` settles it
    /// into exactly one intent.
    private var reorderSessions: [String: ReorderSession] = [:]

    init(curationStore: CurationStore, outbox: Outbox) {
        self.curationStore = curationStore
        self.outbox = outbox
        refresh()
    }

    func refresh() {
        collections = curationStore.fetchCollections()
        memberRevision += 1
    }

    var isEmpty: Bool { collections.isEmpty }

    /// The members of `collectionID`, in position order. An empty
    /// collection returns `[]` — callers render `CollectionDetailView`'s
    /// explanatory empty state rather than treating this as an error.
    func members(of collectionID: String) -> [CurationCollectionMemberRow] {
        _ = memberRevision
        return curationStore.fetchCollectionMembers().filter { $0.collectionID == collectionID }
    }

    @discardableResult
    func createCollection(name: String) -> Bool {
        let id = UUID().uuidString
        guard (try? outbox.enqueue(.collectionCreate(id: id, name: name))) != nil else { return false }
        refresh()
        return true
    }

    @discardableResult
    func renameCollection(_ collectionID: String, name: String) -> Bool {
        guard (try? outbox.enqueue(.collectionRename(collectionID: collectionID, name: name))) != nil else { return false }
        refresh()
        return true
    }

    @discardableResult
    func deleteCollection(_ collectionID: String) -> Bool {
        guard (try? outbox.enqueue(.collectionDelete(collectionID: collectionID))) != nil else { return false }
        refresh()
        return true
    }

    @discardableResult
    func addMember(to collectionID: String, assetSetID: String) -> Bool {
        let existing = members(of: collectionID)
        guard !existing.contains(where: { $0.assetSetID == assetSetID }) else { return false }
        let id = UUID().uuidString
        let position = FractionalPosition.last(existing.map(\.position).max())
        guard (try? outbox.enqueue(.collectionMemberAdd(id: id, collectionID: collectionID, assetSetID: assetSetID, position: position))) != nil else {
            return false
        }
        return true
    }

    @discardableResult
    func removeMember(from collectionID: String, assetSetID: String) -> Bool {
        guard let row = members(of: collectionID).first(where: { $0.assetSetID == assetSetID }) else { return false }
        guard (try? outbox.enqueue(.collectionMemberRemove(rowID: row.id, collectionID: collectionID, assetSetID: assetSetID))) != nil else {
            return false
        }
        return true
    }

    // MARK: - Reorder (settles to exactly one intent per gesture)

    /// Snapshots `collectionID`'s current member order into an
    /// in-memory preview — call once when a drag gesture begins.
    func beginReorderMembers(_ collectionID: String) {
        let session = ReorderSession()
        session.begin(order: members(of: collectionID).map(\.assetSetID))
        reorderSessions[collectionID] = session
    }

    /// Mutates only the in-memory preview order — call as many times as
    /// the drag gesture updates (no outbox write, no network, no
    /// intermediate position ever sent).
    func previewMoveMember(_ collectionID: String, assetSetID: String, to index: Int) {
        reorderSessions[collectionID]?.previewMove(id: assetSetID, to: index)
    }

    /// Settles the drag gesture: computes the moved item's final
    /// neighbours from the in-memory preview order and enqueues exactly
    /// one `.collectionMemberMove` intent naming them — never a whole
    /// ordered list.
    @discardableResult
    func commitReorderMembers(_ collectionID: String, assetSetID: String) -> Bool {
        defer { reorderSessions[collectionID] = nil }
        guard let session = reorderSessions[collectionID] else { return false }
        let existing = members(of: collectionID)
        guard let move = session.commit(id: assetSetID, positionOf: { id in existing.first(where: { $0.assetSetID == id })?.position }) else {
            return false
        }
        guard let row = existing.first(where: { $0.assetSetID == assetSetID }) else { return false }

        guard (try? outbox.enqueue(.collectionMemberMove(
            rowID: row.id, collectionID: collectionID, assetSetID: assetSetID, position: move.position,
            beforeAssetSetID: move.beforeID, afterAssetSetID: move.afterID
        ))) != nil else { return false }
        return true
    }
}
