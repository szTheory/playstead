import Foundation

/// A tiny `Sendable` handle that starts `SaveOutbox.drainOnce(apiClient:)`
/// passes -- the `SaveOutbox` equivalent of `OutboxDrainTrigger`.
///
/// `SaveOutbox.drainOnce` is not actor-isolated the way `OutboxWorker` is
/// (it is a plain method on a plain class), so this trigger serializes
/// passes itself: `fire()` reads the previous `_lastTask` and replaces
/// it with the newly started one INSIDE ONE critical section, then the
/// new task awaits that predecessor before starting its own pass. That
/// single critical section is what makes the chain a single lane: two
/// concurrent `fire()` calls cannot both observe the same predecessor,
/// because the lock serializes the read-and-replace itself, not just
/// each half of it separately. (The sibling `OutboxDrainTrigger` needs
/// no equivalent section — its `OutboxWorker` is actor-isolated and
/// never reads `_lastTask` before starting a pass, so that isolation
/// alone supplies the serialization there.) Without this, two overlapping
/// `fire()` calls could both read `listPending()` before either one's
/// send completed and send the same entry twice.
///
/// `drainCount` and `awaitPending()` exist for the same reason they do on
/// `OutboxDrainTrigger`: they are the observable proof a test asserts
/// against. Their absence for `saveOutbox` is exactly what let this whole
/// class of defect (WINDOWS #42 -- constructed but never drained) go
/// undetected.
final class SaveOutboxDrainTrigger: @unchecked Sendable {
    private let saveOutbox: SaveOutbox
    private let apiClient: APIClient
    private let lock = NSLock()
    private var _drainCount = 0
    private var _lastTask: Task<Int, Never>?

    init(saveOutbox: SaveOutbox, apiClient: APIClient) {
        self.saveOutbox = saveOutbox
        self.apiClient = apiClient
    }

    /// How many drain passes have been started since launch.
    var drainCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _drainCount
    }

    /// Starts one drain pass, serialized behind whatever pass is already
    /// running. Two overlapping `fire()` calls therefore process the
    /// pending set one pass at a time rather than racing the same entry.
    ///
    /// The predecessor read, the `Task` construction, the drain-count
    /// increment, and the `_lastTask` replacement all happen inside ONE
    /// `lock.lock()`/`lock.unlock()` pair. Constructing a `Task` does not
    /// block and does not re-enter the lock, so building it inside the
    /// critical section is safe -- and it is exactly what closes the
    /// race: two concurrent callers can no longer both read the same
    /// `previous` before either one's replacement is published.
    @discardableResult
    func fire() -> Task<Int, Never> {
        let saveOutbox = self.saveOutbox
        let apiClient = self.apiClient

        lock.lock()
        let previous = _lastTask
        let task = Task<Int, Never> {
            _ = await previous?.value
            return await saveOutbox.drainOnce(apiClient: apiClient)
        }
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
