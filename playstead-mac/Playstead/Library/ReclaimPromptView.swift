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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func formatBytes(_ bytes: Int) -> String {
        ByteFormatting.formatBytes(bytes)
    }

    /// The plain, always-present statement that the server retains the
    /// content regardless of what's reclaimed here — pulled into a pure
    /// function so it's testable without hosting the view.
    static let serverRetainsStatement = "Nothing changes on your server — you can download it again anytime."

    enum Automation {
        static let shortfall = "playstead.reclaim.shortfall"
        static let selection = "playstead.reclaim.selection"
        static let raiseQuota = "playstead.reclaim.raise-quota"
        static let confirm = "playstead.reclaim.confirm"
        static let cancel = "playstead.reclaim.cancel"

        static func candidate(_ slot: Int) -> String { "playstead.reclaim.candidate.\(slot)" }
        static func candidateToggle(_ slot: Int) -> String { "\(candidate(slot)).toggle" }
    }

    static func shortfallStatement(limitHit: QuotaLimitKind, shortfallBytes: Int) -> String {
        let limitName = limitHit == .floor ? "free-space floor" : "quota"
        return "This download needs \(formatBytes(shortfallBytes)) more than your \(limitName) allows."
    }

    private var selectedBytes: Int {
        candidates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(Self.shortfallStatement(limitHit: limitHit, shortfallBytes: shortfallBytes))
                .font(.psBody)
                .foregroundStyle(.primary)
                .accessibilityLabel("Storage shortfall")
                .accessibilityValue(String(shortfallBytes))
                .accessibilityIdentifier(Automation.shortfall)

            Text(Self.serverRetainsStatement)
                .font(.psLabel)
                .foregroundStyle(.secondary)

            if canRaiseQuota {
                Button("Raise quota", action: onRaiseQuota)
                    .playsteadFocusable(identifier: Automation.raiseQuota)
            }

            Text("\(selected.count) selected — \(Self.formatBytes(selectedBytes))")
                .font(.psLabel)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reclaim selection")
                .accessibilityValue("count=\(selected.count);bytes=\(selectedBytes)")
                .accessibilityIdentifier(Automation.selection)

            if candidates.isEmpty {
                Text("Nothing to reclaim yet.")
                    .font(.psLabel)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { slot, candidate in
                        HStack {
                            Text(candidate.title)
                            Spacer()
                            Text(Self.formatBytes(candidate.bytes))
                                .foregroundStyle(.secondary)
                            Button(selected.contains(candidate.id) ? "Deselect" : "Select") {
                                if selected.contains(candidate.id) {
                                    selected.remove(candidate.id)
                                } else {
                                    selected.insert(candidate.id)
                                }
                            }
                            .accessibilityLabel("Select \(candidate.title) for reclaim")
                            .playsteadFocusable(identifier: Automation.candidateToggle(slot))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(candidate.title)
                        .accessibilityValue("bytes=\(candidate.bytes);selected=\(selected.contains(candidate.id))")
                        .accessibilityIdentifier(Automation.candidate(slot))
                        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
                        Divider()
                    }
                }

                Button("Reclaim selected") { onReclaim(selected) }
                    .disabled(selected.isEmpty)
                    .playsteadFocusable(identifier: Automation.confirm)
            }

            Button("Cancel", role: .cancel, action: onCancel)
                .playsteadFocusable(identifier: Automation.cancel)
        }
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reclaim storage")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.reclaim)
        .focusSection()
        .animation(
            .easeInOut(duration: StorageMotionContract.duration(for: .eviction, reduceMotion: reduceMotion)),
            value: candidates.count
        )
    }
}
