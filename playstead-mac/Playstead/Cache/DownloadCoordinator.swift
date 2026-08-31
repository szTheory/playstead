import Foundation

/// One observable event `DownloadsView` (and `GameCardView`'s progress
/// ring, via `LibraryViewModel`) can subscribe to. Kept as a flat enum
/// rather than a stored-and-diffed model — every consumer either reacts
/// live or re-derives `AvailabilityState` from disk on its own schedule,
/// per D-21's "never trust remembered state" rule.
enum CoordinatorEvent: Equatable, Sendable {
    case started(itemID: String, assetSetID: String, sha256: String)
    case progress(itemID: String, assetSetID: String, sha256: String, percent: Int)
    case committed(itemID: String, assetSetID: String, sha256: String)
    case blocked(itemID: String, assetSetID: String, reason: String)
    case digestMismatchRequeued(itemID: String, assetSetID: String, sha256: String, attempt: Int)
    case wentOffline
    case resumedOnline
}

/// A Swift `actor` that drives exactly one transfer at a time through the
/// existing `DownloadEngine`, selecting the next item by pin priority
/// first and queue position second, marking it active, publishing
/// progress, and on completion recording the cache object and its verify
/// record. Never opens a second transfer path of its own (D-18) — every
/// committed byte in this phase passes through `DownloadEngine.download`.
///
/// `isPinned` and `quotaCheck` are injected closures rather than direct
/// references to `PinStore`/`QuotaManager`: those types are added in this
/// plan's later tasks, and keeping the coordinator's own selection/gating
/// logic seam-based means this task is independently compilable and
/// testable before either exists, and task 2 wires the real
/// implementations in without changing this actor's shape.
actor DownloadCoordinator {
    private let queue: DownloadQueue
    private let engine: DownloadEngine
    private let cas: CASManager
    private let localStore: LocalStore
    private let reachability: Reachability
    private let blobURL: (String) -> URL

    /// Wired to `PinStore.isPinned(_:)` in task 2. Defaults to "nothing
    /// is pinned," which degrades selection to pure queue-position order.
    var isPinned: (String) -> Bool = { _ in false }
    /// Wired to `QuotaManager.verdict(forAdditional:)` in task 2. Defaults
    /// to "always allow," so this task's tests never see a blocked
    /// verdict unless they explicitly inject one.
    var quotaCheck: (Int) -> (allowed: Bool, reason: String?) = { _ in (true, nil) }

    private var isRunning = false
    private var currentItem: QueueItem?
    private var currentDownloadTask: Task<Void, Never>?
    private var progressByAssetSet: [String: Int] = [:]

    private let eventsContinuation: AsyncStream<CoordinatorEvent>.Continuation
    nonisolated let events: AsyncStream<CoordinatorEvent>

    init(
        queue: DownloadQueue,
        engine: DownloadEngine,
        cas: CASManager,
        localStore: LocalStore,
        reachability: Reachability,
        blobURL: @escaping (String) -> URL
    ) {
        self.queue = queue
        self.engine = engine
        self.cas = cas
        self.localStore = localStore
        self.reachability = reachability
        self.blobURL = blobURL

        var continuation: AsyncStream<CoordinatorEvent>.Continuation!
        self.events = AsyncStream { cont in continuation = cont }
        self.eventsContinuation = continuation

        let progressStream = engine.progress
        Task { [weak self] in
            for await event in progressStream {
                await self?.handleProgress(event)
            }
        }

        reachability.onChange { [weak self] online in
            guard let self else { return }
            Task {
                if online {
                    await self.resumeAfterReachabilityReturn()
                } else {
                    await self.handleOffline()
                }
            }
        }
    }

    /// Kicks off the scheduling loop if it isn't already running. Safe to
    /// call repeatedly (e.g. after every enqueue, and after reachability
    /// returns) — a no-op when a loop is already in flight.
    func start() {
        guard !isRunning else { return }
        guard reachability.isOnline else { return }
        isRunning = true
        Task { await self.runLoop() }
    }

    /// The current transfer progress (0...100) for `assetSetID`'s active
    /// member, if any is currently downloading. `AvailabilityInputs`
    /// callers read this to populate `activeMemberProgressPercent`.
    func progressPercent(forAssetSet assetSetID: String) -> Int? {
        progressByAssetSet[assetSetID]
    }

    /// The sha256 of the member currently being transferred for
    /// `assetSetID`, if any. `AvailabilityInputs` callers read this to
    /// populate `activeMemberSHA`.
    func activeMemberSHA(forAssetSet assetSetID: String) -> String? {
        guard let currentItem, currentItem.assetSetID == assetSetID else { return nil }
        return currentItem.sha256
    }

    private func runLoop() async {
        while true {
            guard reachability.isOnline else {
                isRunning = false
                return
            }
            guard let item = selectNext() else {
                isRunning = false
                return
            }

            let verdict = quotaCheck(item.size)
            guard verdict.allowed else {
                try? queue.pause(id: item.id)
                emit(.blocked(itemID: item.id, assetSetID: item.assetSetID, reason: verdict.reason ?? "quota"))
                isRunning = false
                return
            }

            await process(item)
        }
    }

    /// Selects the next `.waiting` item: pinned asset sets first
    /// (regardless of queue position), then queue position order within
    /// each priority tier.
    private func selectNext() -> QueueItem? {
        let waiting = queue.list().filter { $0.state == .waiting }
        return waiting.sorted { lhs, rhs in
            let lhsPinned = isPinned(lhs.assetSetID)
            let rhsPinned = isPinned(rhs.assetSetID)
            if lhsPinned != rhsPinned { return lhsPinned && !rhsPinned }
            return lhs.position < rhs.position
        }.first
    }

    private func process(_ item: QueueItem) async {
        currentItem = item
        try? queue.markActive(id: item.id)
        emit(.started(itemID: item.id, assetSetID: item.assetSetID, sha256: item.sha256))

        // The download itself runs inside a cancellable child `Task` (so
        // `handleOffline()` can interrupt an in-flight transfer), but the
        // entire transfer/outcome-handling body (`runDownload`) is its
        // own actor-isolated method — every `engine`/`queue`/`cas` access
        // therefore happens on this actor's own isolation domain, never
        // reached from outside it.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runDownload(item)
        }
        currentDownloadTask = task
        await task.value
        currentDownloadTask = nil
        currentItem = nil
        progressByAssetSet.removeValue(forKey: item.assetSetID)
    }

    private func runDownload(_ item: QueueItem) async {
        do {
            try await engine.download(sha256: item.sha256, from: blobURL(item.sha256), expectedSize: item.size)
            handleSuccess(item)
        } catch is CancellationError {
            // Offline handling already reset this item's state to
            // `.waiting` before cancelling — nothing further to do.
        } catch let error as DownloadError {
            handleDownloadError(item, error: error)
        } catch {
            // A transport failure the engine itself couldn't recover
            // from (or a cancellation surfaced as a plain `URLError`,
            // e.g. `.cancelled`) — reset the row to `.waiting` so the
            // scheduling loop (or the next reachability return) can
            // re-select it rather than leaving it stuck `.active` with
            // no in-flight task behind it.
            try? queue.resume(id: item.id)
        }
    }

    private func handleSuccess(_ item: QueueItem) {
        if let record = cas.verifyRecord(for: item.sha256) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let mtimeMS = Int(record.mtime * 1000)
            try? localStore.connection.execute(
                """
                INSERT INTO cache_objects
                    (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(sha256) DO UPDATE SET
                    last_used_at = excluded.last_used_at,
                    verify_size = excluded.verify_size,
                    verify_inode = excluded.verify_inode,
                    verify_mtime_ms = excluded.verify_mtime_ms;
                """,
                params: [item.sha256, record.size, timestamp, timestamp, record.size, Int(record.inode), mtimeMS]
            )
        }
        try? queue.dequeue(id: item.id)
        emit(.committed(itemID: item.id, assetSetID: item.assetSetID, sha256: item.sha256))
    }

    /// A digest mismatch is a corrupted local copy, not an incident
    /// (D-23): `DownloadEngine` already quarantined the bad partial, so
    /// all this actor does is re-enqueue with an incremented attempt
    /// count and a plainly worded, no-blame event for the UI.
    private func handleDownloadError(_ item: QueueItem, error: DownloadError) {
        guard case .digestMismatch = error else {
            try? queue.resume(id: item.id)
            return
        }
        try? queue.incrementAttempt(id: item.id)
        try? queue.resume(id: item.id)
        emit(.digestMismatchRequeued(itemID: item.id, assetSetID: item.assetSetID, sha256: item.sha256, attempt: item.attemptCount + 1))
    }

    /// Reachability returned: emit the calm "we're back" event and
    /// resume the scheduling loop with no user action required (D-22).
    private func resumeAfterReachabilityReturn() {
        emit(.resumedOnline)
        start()
    }

    /// Reachability dropped: cancel the in-flight transfer (if any) and
    /// move every active row back to `.waiting` — a normal, quiet state
    /// with its own calm copy, never an error banner (D-22).
    private func handleOffline() {
        currentDownloadTask?.cancel()
        try? queue.pauseAllActive()
        isRunning = false
        emit(.wentOffline)
    }

    private func handleProgress(_ event: DownloadEngine.DownloadProgressEvent) {
        guard let currentItem, currentItem.sha256 == event.sha256 else { return }
        let percent: Int
        if let expected = event.expectedSize, expected > 0 {
            percent = max(0, min(100, Int((Double(event.bytesWritten) / Double(expected)) * 100)))
        } else {
            percent = 0
        }
        progressByAssetSet[currentItem.assetSetID] = percent
        emit(.progress(itemID: currentItem.id, assetSetID: currentItem.assetSetID, sha256: currentItem.sha256, percent: percent))
    }

    private func emit(_ event: CoordinatorEvent) {
        eventsContinuation.yield(event)
    }
}
