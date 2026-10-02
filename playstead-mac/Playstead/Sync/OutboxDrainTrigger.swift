import Foundation

/// A tiny `Sendable` handle that starts `OutboxWorker.drainOnce()` passes.
///
/// It exists so the three drain triggers (after every `Outbox.enqueue`, on
/// reachability being regained, and on `scenePhase` becoming `.active`)
/// can be expressed as `@Sendable` closures that capture *this* rather
/// than capturing the `@MainActor` `AppEnvironment`, and so a test can
/// assert that the worker is genuinely running in the assembled app —
/// `drainCount` is the observable proof, and `awaitPending()` lets a test
/// await every pass currently in flight instead of polling.
final class OutboxDrainTrigger: @unchecked Sendable {
    private let worker: OutboxWorker
    private let lock = NSLock()
    private var _drainCount = 0
    private var _activePasses = 0
    private var _waiters: [CheckedContinuation<Void, Never>] = []

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
    /// calls are safe; waiters are tracked so a test does not return while
    /// an earlier pass is still awaiting its transport request.
    @discardableResult
    func fire() -> Task<OutboxDrainResult, Never> {
        let worker = self.worker
        lock.lock()
        _drainCount += 1
        _activePasses += 1
        lock.unlock()

        let task = Task { [self, worker] in
            defer { finishPass() }
            return await worker.drainOnce()
        }
        return task
    }

    /// Awaits all drain passes that are active now, including overlapping
    /// passes whose worker calls may finish in a different order.
    func awaitPending() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            guard _activePasses > 0 else {
                lock.unlock()
                continuation.resume()
                return
            }
            _waiters.append(continuation)
            lock.unlock()
        }
    }

    private func finishPass() {
        lock.lock()
        _activePasses -= 1
        let waiters = _activePasses == 0 ? _waiters : []
        if _activePasses == 0 { _waiters.removeAll() }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}
