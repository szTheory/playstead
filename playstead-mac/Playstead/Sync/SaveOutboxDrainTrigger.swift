import Foundation

/// A tiny `Sendable` handle that starts `SaveOutbox.drainOnce(apiClient:)`
/// passes -- the `SaveOutbox` equivalent of `OutboxDrainTrigger`.
///
/// `SaveOutbox.drainOnce` is not actor-isolated the way `OutboxWorker` is
/// (it is a plain method on a plain class), so this trigger serializes
/// passes itself: `fire()` awaits the previously started task before
/// starting the next one, standing in for the actor isolation the
/// curation drain trigger gets for free. Without this, two overlapping
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
    @discardableResult
    func fire() -> Task<Int, Never> {
        let saveOutbox = self.saveOutbox
        let apiClient = self.apiClient

        lock.lock()
        let previous = _lastTask
        lock.unlock()

        let task = Task<Int, Never> {
            _ = await previous?.value
            return await saveOutbox.drainOnce(apiClient: apiClient)
        }

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
