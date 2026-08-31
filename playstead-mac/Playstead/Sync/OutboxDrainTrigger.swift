import Foundation

/// A tiny `Sendable` handle that starts `OutboxWorker.drainOnce()` passes.
///
/// It exists so the three drain triggers (after every `Outbox.enqueue`, on
/// reachability being regained, and on `scenePhase` becoming `.active`)
/// can be expressed as `@Sendable` closures that capture *this* rather
/// than capturing the `@MainActor` `AppEnvironment`, and so a test can
/// assert that the worker is genuinely running in the assembled app —
/// `drainCount` is the observable proof, and `awaitPending()` lets a test
/// await the pass a trigger actually started instead of polling.
final class OutboxDrainTrigger: @unchecked Sendable {
    private let worker: OutboxWorker
    private let lock = NSLock()
    private var _drainCount = 0
    private var _lastTask: Task<OutboxDrainResult, Never>?

    init(worker: OutboxWorker) {
        self.worker = worker
    }

    /// How many drain passes have been started since launch.
    var drainCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _drainCount
    }

    /// Starts one drain pass. The worker is an actor, so overlapping
    /// calls serialize rather than racing the same entry.
    @discardableResult
    func fire() -> Task<OutboxDrainResult, Never> {
        let worker = self.worker
        let task = Task { await worker.drainOnce() }
        lock.lock()
        _drainCount += 1
        _lastTask = task
        lock.unlock()
        return task
    }

    /// Awaits the most recently started pass, if any.
    func awaitPending() async {
        lock.lock()
        let task = _lastTask
        lock.unlock()
        _ = await task?.value
    }
}
