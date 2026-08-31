import Foundation

/// The play queue: enqueue/dequeue/reorder, offline-first over `Outbox`
/// (plan 03-08 task 2). Mirrors `CollectionsViewModel`'s reorder
/// discipline exactly (preview many, commit one intent) minus the
/// per-collection scoping — there is exactly one queue per user.
@Observable
final class QueueViewModel {
    private let curationStore: CurationStore
    private let outbox: Outbox

    private(set) var items: [CurationQueueItemRow] = []
    private var previewOrder: [String]?

    init(curationStore: CurationStore, outbox: Outbox) {
        self.curationStore = curationStore
        self.outbox = outbox
        refresh()
    }

    func refresh() {
        items = curationStore.fetchQueueItems()
    }

    var isEmpty: Bool { items.isEmpty }

    func isQueued(assetSetID: String) -> Bool {
        items.contains { $0.assetSetID == assetSetID }
    }

    @discardableResult
    func enqueue(assetSetID: String) -> Bool {
        guard !isQueued(assetSetID: assetSetID) else { return false }
        let id = UUID().uuidString
        let position = FractionalPosition.last(items.map(\.position).max())
        guard (try? outbox.enqueue(.queueEnqueue(id: id, assetSetID: assetSetID, position: position))) != nil else { return false }
        refresh()
        return true
    }

    @discardableResult
    func dequeue(assetSetID: String) -> Bool {
        guard let row = items.first(where: { $0.assetSetID == assetSetID }) else { return false }
        guard (try? outbox.enqueue(.queueDequeue(rowID: row.id, assetSetID: assetSetID))) != nil else { return false }
        refresh()
        return true
    }

    // MARK: - Reorder (settles to exactly one intent per gesture)

    func beginReorder() {
        previewOrder = items.map(\.assetSetID)
    }

    func previewMove(assetSetID: String, to index: Int) {
        guard var order = previewOrder else { return }
        order.removeAll { $0 == assetSetID }
        let clamped = max(0, min(index, order.count))
        order.insert(assetSetID, at: clamped)
        previewOrder = order
    }

    @discardableResult
    func commitReorder(assetSetID: String) -> Bool {
        defer { previewOrder = nil }
        guard let order = previewOrder, let movedIndex = order.firstIndex(of: assetSetID) else { return false }
        guard let row = items.first(where: { $0.assetSetID == assetSetID }) else { return false }

        let beforeID = movedIndex > 0 ? order[movedIndex - 1] : nil
        let afterID = movedIndex < order.count - 1 ? order[movedIndex + 1] : nil
        let beforePosition = beforeID.flatMap { id in items.first(where: { $0.assetSetID == id })?.position }
        let afterPosition = afterID.flatMap { id in items.first(where: { $0.assetSetID == id })?.position }
        let newPosition = FractionalPosition.between(beforePosition, afterPosition)

        guard (try? outbox.enqueue(.queueMove(
            rowID: row.id, assetSetID: assetSetID, position: newPosition,
            beforeAssetSetID: beforeID, afterAssetSetID: afterID
        ))) != nil else { return false }
        return true
    }
}
