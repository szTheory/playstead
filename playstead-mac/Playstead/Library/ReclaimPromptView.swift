import SwiftUI

/// One candidate a user could reclaim to make room — a lightweight,
/// self-contained projection (not `EvictionPlanner.EvictionCandidate`
/// directly, so this view has no forward dependency on plan 03-07 task
/// 3's type; `StorageView` can adapt either shape into this one).
struct ReclaimCandidateRow: Identifiable, Equatable {
    let id: String
    let title: String
    let bytes: Int
    /// D-40's interruptive-tier input: how many of this game's save
    /// revisions exist only on this Mac, read from committed local
    /// state. Zero means reclaiming this candidate raises no
    /// interruptive modal at all.
    ///
    /// No default (MC-01): a defaulted zero here is precisely how three
    /// separate production call sites each silently omitted it and the
    /// D-40 gate went permanently dark. Every caller must now supply a
    /// real value or fail to compile.
    var onlyOnThisMacCount: Int
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
    /// MC-02: the real escape hatch — invoked with the affected
    /// candidate ids when the user chooses "Export saves…" instead of
    /// the destructive action. Required (no default): a caller that
    /// forgets to wire this is the same silent-omission failure mode
    /// MC-02 was.
    let onExportOnlyCopy: (Set<String>) -> Void

    @State private var selected: Set<String> = []
    @State private var pendingSelection: Set<String>?
    @State private var pendingExportCandidateIDs: Set<String> = []
    @State private var pendingOnlyOnThisMacCount = 0
    @State private var pendingOnlyOnThisMacTitle = ""
    @State private var showOnlyCopyInterruption = false
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
                                .accessibilityLabel(candidate.title)
                                .accessibilityValue("bytes=\(candidate.bytes);selected=\(selected.contains(candidate.id))")
                                .accessibilityIdentifier(Automation.candidate(slot))
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
                        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
                        Divider()
                    }
                }

                Button("Reclaim selected") {
                    let selection = selected
                    let affected = candidates.filter { selection.contains($0.id) && $0.onlyOnThisMacCount > 0 }
                    let onlyOnThisMacCount = affected.reduce(0) { $0 + $1.onlyOnThisMacCount }
                    if OnlyCopyInterruptionGate.shouldPresent(onlyOnThisMacCount: onlyOnThisMacCount) {
                        pendingSelection = selection
                        pendingExportCandidateIDs = Set(affected.map(\.id))
                        pendingOnlyOnThisMacCount = onlyOnThisMacCount
                        pendingOnlyOnThisMacTitle = affected.count == 1 ? affected[0].title : "\(affected.count) games"
                        showOnlyCopyInterruption = true
                    } else {
                        selected.removeAll()
                        onReclaim(selection)
                    }
                }
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
        .animation(
            .easeInOut(duration: StorageMotionContract.duration(for: .eviction, reduceMotion: reduceMotion)),
            value: candidates.count
        )
        .sheet(isPresented: $showOnlyCopyInterruption) {
            OnlyCopyInterruptiveSheet(
                onlyOnThisMacCount: pendingOnlyOnThisMacCount,
                title: pendingOnlyOnThisMacTitle,
                onExport: {
                    // MC-02: the default, safest-looking button must do
                    // the real export, not just close the sheet — and
                    // clearing `pendingSelection` here (not just in the
                    // cancel/remove-anyway branches) is what stops the
                    // deferred destructive action from ever firing after
                    // the user chose the safe path instead.
                    showOnlyCopyInterruption = false
                    onExportOnlyCopy(pendingExportCandidateIDs)
                    pendingSelection = nil
                    pendingExportCandidateIDs = []
                },
                onCancel: {
                    showOnlyCopyInterruption = false
                    pendingSelection = nil
                },
                onRemoveAnyway: {
                    showOnlyCopyInterruption = false
                    if let pendingSelection {
                        selected.removeAll()
                        onReclaim(pendingSelection)
                    }
                    self.pendingSelection = nil
                }
            )
        }
    }
}
