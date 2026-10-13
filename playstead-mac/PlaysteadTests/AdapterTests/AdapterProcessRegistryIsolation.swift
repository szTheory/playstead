import Foundation
@testable import Playstead

/// Test-only isolation for `AdapterProcessRegistry`.
///
/// The registry's termination sweep terminates **every** process
/// registered in it, and it fires on `NSApplication.willTerminateNotification`.
/// With one process-global registry listening on `NotificationCenter.default`,
/// the single test that legitimately exercises that sweep
/// (`RelaunchTests.testRegisteredAdapterProcessIsTerminatedWhenApplicationTerminationHandlerRuns`)
/// reaches into every *other* test's child process — observed as a
/// spawned binary being SIGTERMed instead of exiting on its own
/// (`unknown(status: 15, reason: "uncaughtSignal")` where `clean` was
/// expected) and as termination handlers that never fire, which then
/// time out the exit expectations in `AdapterWiringTests`,
/// `LaunchMutexTests` and `PlaySessionTests` (WINDOWS #86).
///
/// This does **not** paper over a timing problem: it removes the
/// coupling itself. A registry built here observes a `NotificationCenter`
/// that nothing else holds, so a sweep posted by one test is
/// unreachable from any other test's processes by construction.
extension AdapterProcessRegistry {
    /// A registry whose termination sweep can only ever be triggered by
    /// `center`, and which no other test shares.
    static func isolatedForTesting(
        center: NotificationCenter = NotificationCenter()
    ) -> AdapterProcessRegistry {
        AdapterProcessRegistry(notificationCenter: center)
    }
}
