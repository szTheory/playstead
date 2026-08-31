import SwiftUI
import AppKit

/// Observes and publishes the system's reduced-motion accessibility
/// setting (03-UI-SPEC.md Motion & Focus Specification, D-16). The
/// determinate progress fill itself is never affected by this type — it
/// carries information a user needs regardless of motion preference;
/// only a morph, a directional focus transition, or a status crossfade
/// collapses to an instant change when reduced motion is on. Removing
/// the progress fill under reduced motion would trade one accessibility
/// need for the loss of the only signal that a long download is
/// advancing — this type exists specifically so no caller can make that
/// mistake by construction: it only ever offers a *duration*, never a
/// way to suppress a determinate value.
@MainActor
@Observable
final class MotionPreference {
    private(set) var reduceMotionEnabled: Bool

    /// Injectable so tests toggle this without touching the real system
    /// setting or requiring Accessibility permissions in CI.
    private let poll: () -> Bool
    // `nonisolated(unsafe)`: deinit cannot hop to the main actor to read
    // an isolated property, but this token is only ever written once (in
    // init, on the main actor) and read/cleared once (in deinit, at most
    // once per instance) — there is no concurrent access to guard against.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(poll: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.poll = poll
        self.reduceMotionEnabled = poll()
        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Re-reads the current system setting — production code relies on
    /// the notification observer above; tests call this directly after
    /// swapping what `poll` returns.
    func refresh() {
        reduceMotionEnabled = poll()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The duration a morph, a directional focus transition, or a
    /// status crossfade should use: zero (an instant change) under
    /// reduced motion, the design system's normal duration otherwise.
    /// Never consulted by anything that renders a determinate progress
    /// fraction — that value is computed independently of motion
    /// preference by design (see `ProgressFillState`).
    var morphAndTransitionDuration: Double {
        reduceMotionEnabled ? 0 : 0.2
    }
}

/// The determinate progress fraction a downloading card/row renders —
/// deliberately computed with no dependency on `MotionPreference` at
/// all, so "reduced motion never removes progress information" is true
/// by construction rather than by a caller remembering to check a flag.
struct ProgressFillState: Equatable {
    let fraction: Double

    init(percent: Int) {
        fraction = Double(max(0, min(100, percent))) / 100
    }
}
