import SwiftUI

/// One row `DownloadsView` renders — a plain, `Equatable` projection of a
/// `QueueItem` plus its resolved display title and (when actively
/// transferring) progress percent, kept separate from `QueueItem` itself
/// so this view stays fully testable/pure without a live `DownloadQueue`.
struct DownloadRow: Identifiable, Equatable {
    let id: String
    let assetSetID: String
    let title: String
    let sha256: String
    let sizeBytes: Int
    let state: QueueItemState
    let progressPercent: Int?
}

/// Lists the persistent download queue with per-item pause, resume,
/// cancel, and reorder, and an overall progress summary. An empty queue
/// renders as a calm empty state (never an error or a blank pane); a
/// queue of one item behaves identically to a queue of many — no
/// special-casing on `rows.count`.
struct DownloadsView: View {
    let rows: [DownloadRow]
    let onPause: (String) -> Void
    let onResume: (String) -> Void
    let onCancel: (String) -> Void
    let onMoveUp: (String) -> Void
    let onMoveDown: (String) -> Void

    /// A single-line summary of queue activity — pure, so it's directly
    /// testable without hosting the view.
    static func summary(for rows: [DownloadRow]) -> String {
        guard !rows.isEmpty else { return "Your queue is empty." }
        let activeCount = rows.filter { $0.state == .active }.count
        let waitingCount = rows.filter { $0.state == .waiting }.count
        let pausedCount = rows.filter { $0.state == .paused }.count

        var parts: [String] = []
        if activeCount > 0 { parts.append("\(activeCount) downloading") }
        if waitingCount > 0 { parts.append("\(waitingCount) queued") }
        if pausedCount > 0 { parts.append("\(pausedCount) paused") }
        return parts.isEmpty ? "Your queue is empty." : parts.joined(separator: ", ")
    }

    enum Automation {
        static let summary = "playstead.downloads.summary"

        static func row(_ slot: Int) -> String { "playstead.download.row.\(slot)" }
        static func state(_ slot: Int) -> String { "\(row(slot)).state" }
        static func progress(_ slot: Int) -> String { "\(row(slot)).progress" }
        static func moveUp(_ slot: Int) -> String { "\(row(slot)).move-up" }
        static func moveDown(_ slot: Int) -> String { "\(row(slot)).move-down" }
        static func pauseResume(_ slot: Int) -> String { "\(row(slot)).pause-resume" }
        static func cancel(_ slot: Int) -> String { "\(row(slot)).cancel" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if rows.isEmpty {
                Text("Add a game to your queue to keep it in mind.")
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
                    .padding(DesignTokens.Spacing.lg)
            } else {
                Text(Self.summary(for: rows))
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .accessibilityLabel("Download queue summary")
                    .accessibilityValue(Self.summary(for: rows))
                    .accessibilityIdentifier(Automation.summary)

                List(Array(rows.enumerated()), id: \.element.id) { slot, row in
                    DownloadQueueRowView(
                        row: row,
                        automationSlot: slot,
                        onPause: onPause,
                        onResume: onResume,
                        onCancel: onCancel,
                        onMoveUp: onMoveUp,
                        onMoveDown: onMoveDown
                    )
                }
            }
        }
    }
}

private struct DownloadQueueRowView: View {
    let row: DownloadRow
    let automationSlot: Int
    let onPause: (String) -> Void
    let onResume: (String) -> Void
    let onCancel: (String) -> Void
    let onMoveUp: (String) -> Void
    let onMoveDown: (String) -> Void

    private var displayTitle: String {
        row.title.isEmpty ? "Untitled" : row.title
    }

    private var stateLabel: String {
        switch row.state {
        case .waiting: return "Queued"
        case .active: return row.progressPercent.map { "Downloading — \($0)%" } ?? "Downloading"
        case .paused: return "Paused"
        case .cancelled: return "Cancelled"
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(displayTitle)
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(stateLabel)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityLabel("Download state")
                    .accessibilityValue(row.state.rawValue)
                    .accessibilityIdentifier(DownloadsView.Automation.state(automationSlot))
            }

            Spacer()

            if row.state == .active, let percent = row.progressPercent {
                ProgressView(value: Double(percent), total: 100)
                    .progressViewStyle(.circular)
                    .frame(width: DesignTokens.InteractiveTarget.minimum, height: DesignTokens.InteractiveTarget.minimum)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue("\(percent) percent")
                    .accessibilityIdentifier(DownloadsView.Automation.progress(automationSlot))
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    onMoveUp(row.id)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Move \(displayTitle) up in queue")
                .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
                .playsteadFocusable(identifier: DownloadsView.Automation.moveUp(automationSlot))

                Button {
                    onMoveDown(row.id)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Move \(displayTitle) down in queue")
                .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
                .playsteadFocusable(identifier: DownloadsView.Automation.moveDown(automationSlot))

                if row.state == .paused {
                    Button("Resume") { onResume(row.id) }
                        .accessibilityLabel("Resume downloading \(displayTitle)")
                        .playsteadFocusable(identifier: DownloadsView.Automation.pauseResume(automationSlot))
                } else if row.state == .active || row.state == .waiting {
                    Button("Pause") { onPause(row.id) }
                        .accessibilityLabel("Pause downloading \(displayTitle)")
                        .playsteadFocusable(identifier: DownloadsView.Automation.pauseResume(automationSlot))
                }

                Button("Cancel") { onCancel(row.id) }
                    .accessibilityLabel("Cancel downloading \(displayTitle)")
                    .playsteadFocusable(identifier: DownloadsView.Automation.cancel(automationSlot))
            }
        }
        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(displayTitle)
        .accessibilityValue("\(row.state.rawValue), \(row.sizeBytes) bytes")
        .accessibilityIdentifier(DownloadsView.Automation.row(automationSlot))
    }
}
