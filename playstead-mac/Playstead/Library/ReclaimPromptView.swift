import SwiftUI

/// One candidate a user could reclaim to make room — a lightweight,
/// self-contained projection (not `EvictionPlanner.EvictionCandidate`
/// directly, so this view has no forward dependency on plan 03-07 task
/// 3's type; `StorageView` can adapt either shape into this one).
struct ReclaimCandidateRow: Identifiable, Equatable {
    let id: String
    let title: String
    let bytes: Int
}

/// Shown when `DownloadCoordinator` reports a blocked `QuotaVerdict`.
/// States the shortfall in bytes, offers to raise the quota where the
/// floor permits, and offers to reclaim from an ordered candidate list —
/// and does not delete anything itself; every deletion goes through
/// `EvictionPlanner.execute(_:)` behind an explicit user confirmation
/// (D-21).
struct ReclaimPromptView: View {
    let limitHit: QuotaLimitKind
    let shortfallBytes: Int
    let canRaiseQuota: Bool
    let candidates: [ReclaimCandidateRow]
    let onRaiseQuota: () -> Void
    let onReclaim: (Set<String>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<String> = []

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatBytes(_ bytes: Int) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    /// The plain, always-present statement that the server retains the
    /// content regardless of what's reclaimed here — pulled into a pure
    /// function so it's testable without hosting the view.
    static let serverRetainsStatement = "Nothing changes on your server — you can download it again anytime."

    static func shortfallStatement(limitHit: QuotaLimitKind, shortfallBytes: Int) -> String {
        let limitName = limitHit == .floor ? "free-space floor" : "quota"
        return "This download needs \(formatBytes(shortfallBytes)) more than your \(limitName) allows."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(Self.shortfallStatement(limitHit: limitHit, shortfallBytes: shortfallBytes))
                .font(.psBody)
                .foregroundStyle(DesignTokens.textPrimary)

            Text(Self.serverRetainsStatement)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)

            if canRaiseQuota {
                Button("Raise quota", action: onRaiseQuota)
            }

            if candidates.isEmpty {
                Text("Nothing to reclaim yet.")
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            } else {
                List(candidates, selection: $selected) { candidate in
                    HStack {
                        Text(candidate.title)
                        Spacer()
                        Text(Self.formatBytes(candidate.bytes))
                            .foregroundStyle(DesignTokens.textMuted)
                    }
                    .tag(candidate.id)
                }

                Button("Reclaim selected") { onReclaim(selected) }
                    .disabled(selected.isEmpty)
            }

            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
