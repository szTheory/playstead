#if DEBUG && UI_TESTING
import SwiftUI

/// Finite, isolated presentation review. This root never constructs the app
/// environment, touches a store or Keychain, or starts a network transfer.
enum UITestMotionReviewMode: String {
    case normal, slow, reduced

    static var requested: Self? {
        ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_MOTION_REVIEW"].flatMap(Self.init(rawValue:))
    }
}

struct MotionReviewHarnessRootView: View {
    let mode: UITestMotionReviewMode
    @State private var state: QueueItemState = .waiting
    @State private var percent = 42
    @State private var pending = false
    @State private var phase = "queued"

    private var status: LibraryStatus {
        switch state {
        case .waiting: .queued
        case .active: .downloading(percent: percent)
        case .paused: .serverOnly
        case .cancelled: .needsAttention
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Motion review").font(.psHeading)
            HStack(spacing: DesignTokens.Spacing.sm) {
                StatusSlotView(statuses: [status], title: "Synthetic Motion Fixture")
                Text(status.listViewLabel).font(.psLabel)
            }
            DownloadsView(
                rows: [
                    DownloadRow(id: "motion", assetSetID: "synthetic-motion", title: "Synthetic Motion Fixture",
                                sha256: String(repeating: "a", count: 64), sizeBytes: 1_000,
                                state: state, progressPercent: state == .active ? percent : nil),
                    DownloadRow(id: "stationary", assetSetID: "synthetic-stationary", title: "Stationary queued row",
                                sha256: String(repeating: "b", count: 64), sizeBytes: 1_000,
                                state: .waiting, progressPercent: nil)
                ],
                onPause: { _ in }, onResume: { _ in }, onCancel: { _ in },
                onMoveUp: { _ in }, onMoveDown: { _ in }
            )
            HStack {
                Button("Start download") { schedule(.active, phase: "active-42") }
                    .accessibilityIdentifier("playstead.motion.start")
                Button("Advance to 73%") {
                    percent = 73
                    phase = "active-73"
                }
                .disabled(state != .active || pending)
                .accessibilityIdentifier("playstead.motion.progress")
                Button("Pause download") { schedule(.paused, phase: "paused") }
                    .disabled(state != .active)
                    .accessibilityIdentifier("playstead.motion.pause")
            }
            .disabled(pending)
            Text(phase)
                .accessibilityIdentifier("playstead.motion.phase")
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 820, height: 340)
        .background(DesignTokens.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playstead.motion.review")
    }

    /// Delay the semantic change so screenshot acquisition begins before it.
    /// Byte updates above stay immediate and never share this transaction.
    private func schedule(_ next: QueueItemState, phase nextPhase: String) {
        pending = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            state = next
            phase = nextPhase
            pending = false
        }
    }
}
#endif
