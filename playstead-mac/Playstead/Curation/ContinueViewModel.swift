import Foundation

/// Continue: recently played games minus dismissals, derived on read
/// from the local mirror — never a stored rule set the user edits
/// (matching the server's identical `Playstead.Curation.list_continue/1`
/// derivation). Continue's copy promises recency only; save continuity
/// does not exist until a later phase, and a promise made here would be
/// discovered as false at the worst moment.
@Observable
final class ContinueViewModel {
    private let curationStore: CurationStore
    private let outbox: Outbox

    private(set) var items: [CurationRecentRow] = []

    init(curationStore: CurationStore, outbox: Outbox) {
        self.curationStore = curationStore
        self.outbox = outbox
        refresh()
    }

    func refresh() {
        items = Self.deriveContinue(recent: curationStore.fetchRecent(), dismissals: curationStore.fetchContinueDismissals())
    }

    var isEmpty: Bool { items.isEmpty }

    /// Pure so it can be asserted directly by tests — Continue is
    /// recent rows whose asset set has not been locally dismissed.
    ///
    /// Known, bounded gap (see this plan's SUMMARY): the server's own
    /// `list_continue/1` also auto-restores a dismissed game to
    /// Continue once it is played again, by comparing `dismissed_at`
    /// against the latest session's start time read-side. The journal's
    /// `continue_dismissal` payload carries no such timestamp
    /// (`Playstead.Sync.CurationPayload`'s `continue_dismissal` clause —
    /// out of this plan's file scope), so this client instead un-
    /// dismisses locally, explicitly, the moment `PlaySessionRecorder`
    /// (task 3) records a new session for that asset set — see its doc
    /// comment.
    static func deriveContinue(recent: [CurationRecentRow], dismissals: [CurationContinueDismissalRow]) -> [CurationRecentRow] {
        let dismissedAssetSetIDs = Set(dismissals.map(\.assetSetID))
        return recent.filter { !dismissedAssetSetIDs.contains($0.assetSetID) }
    }

    @discardableResult
    func dismiss(assetSetID: String) -> Bool {
        let id = UUID().uuidString
        guard (try? outbox.enqueue(.continueDismiss(id: id, assetSetID: assetSetID))) != nil else { return false }
        refresh()
        return true
    }
}
