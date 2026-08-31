import Foundation
#if canImport(Network)
import Network
#endif

/// Publishes network reachability so `DownloadCoordinator` can treat
/// "queued while offline" as a normal, quiet state (its own copy, never
/// an error banner) rather than a failure — and resume transfers on its
/// own the moment reachability returns, with no user action (D-22).
///
/// Kept intentionally tiny and injectable: production wraps `NWPathMonitor`;
/// tests construct a `Reachability` and flip `isOnline` directly with
/// `simulate(online:)`, with no real network dependency.
final class Reachability: @unchecked Sendable {
    /// Injected by production code; `nil` in tests using `simulate(online:)`.
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif
    private let queue = DispatchQueue(label: "dev.playstead.mac.reachability")
    private let lock = NSLock()
    private var _isOnline: Bool
    private var observers: [(Bool) -> Void] = []

    /// The current reachability state, safe to read from any thread.
    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOnline
    }

    /// `startOnline` lets tests construct an already-offline instance
    /// without needing to call `simulate` before the first read.
    init(startOnline: Bool = true, monitorAutomatically: Bool = true) {
        self._isOnline = startOnline

        #if canImport(Network)
        if monitorAutomatically {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                self?.setOnline(path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
        #endif
    }

    /// Registers a callback invoked (on an unspecified queue) every time
    /// reachability changes, including the transition back to online that
    /// must resume the coordinator with no user action.
    func onChange(_ callback: @escaping (Bool) -> Void) {
        lock.lock()
        observers.append(callback)
        lock.unlock()
    }

    /// Test-only: directly sets reachability, invoking any registered
    /// observers exactly as a real `NWPathMonitor` transition would.
    func simulate(online: Bool) {
        setOnline(online)
    }

    private func setOnline(_ online: Bool) {
        lock.lock()
        let changed = _isOnline != online
        _isOnline = online
        let callbacks = observers
        lock.unlock()

        guard changed else { return }
        for callback in callbacks {
            callback(online)
        }
    }
}
