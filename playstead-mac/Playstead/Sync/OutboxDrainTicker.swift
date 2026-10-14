import Foundation

/// The fourth drain trigger: time.
///
/// The other three are all *edges* — an enqueue, reachability being
/// regained, the scene becoming active — and between them they leave a
/// real, reachable hole. `Reachability` wraps `NWPathMonitor`, which
/// reports whether this Mac has a network path, not whether the paired
/// server is answering. A server that goes away and comes back without the
/// Mac's own network changing (a stopped container, a restarted service, a
/// server reboot) fires no edge at all, so an entry that failed while the
/// server was down waited for the user to focus the window or for some
/// unrelated enqueue to happen to fire a pass.
///
/// Observed 2026-09-13 (WINDOWS #77): two `play_session_record` entries
/// queued while the reverse proxy was stopped were still `pending` and
/// undelivered several minutes after it was answering `/healthz` again,
/// with `next_retry_at` long past — eligible under `listPending`, and
/// simply never triggered. Restarting the server woke nothing, and in-app
/// sidebar navigation did not either (trigger 3 needs a real scene
/// activation, not mere interaction).
///
/// Deliberately a plain periodic tick rather than a server-reachability
/// probe. A probe is a guess about when the server came back; the tick
/// needs no such guess, and the per-entry backoff (`Outbox.retryDelay`)
/// already decides which entries are actually eligible on any given pass —
/// so a pass with nothing due is a single indexed query that sends no
/// requests. The cost of being wrong about the interval is bounded in one
/// direction only, which is the right shape for a delivery guarantee.
final class OutboxDrainTicker: @unchecked Sendable {
    /// 60s: slow enough that a pass with nothing due is negligible, fast
    /// enough that "the server came back" is measured in about a minute
    /// rather than in whenever the user next focuses the window.
    static let defaultInterval: TimeInterval = 60

    private let interval: TimeInterval
    private let onTick: @Sendable () -> Void
    private let lock = NSLock()
    private var _tickCount = 0
    private var task: Task<Void, Never>?

    init(interval: TimeInterval = OutboxDrainTicker.defaultInterval, onTick: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    /// How many ticks have fired since `start()`. The observable proof that
    /// this is running in the assembled app, matching
    /// `OutboxDrainTrigger.drainCount`'s purpose.
    var tickCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _tickCount
    }

    /// Idempotent: a second `start()` does not create a second loop.
    func start() {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            return
        }
        let interval = self.interval
        let onTick = self.onTick
        task = Task { [weak self] in
            // Sleeps first, so starting the ticker is not itself a drain —
            // the composition root already fires the other triggers.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.recordTick()
                onTick()
            }
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let running = task
        task = nil
        lock.unlock()
        running?.cancel()
    }

    private func recordTick() {
        lock.lock()
        _tickCount += 1
        lock.unlock()
    }
}
