import SwiftUI

/// The three storage transitions whose normal and reduced-motion timing is
/// part of checkpoint 5. Determinate progress is deliberately absent from
/// this API: `ProgressFillState` remains information-bearing in both modes.
enum StorageMotionContract {
    enum Phase: CaseIterable, Hashable {
        case status
        case completion
        case eviction
    }

    static let normalDuration: Double = 0.2

    static func duration(for phase: Phase, reduceMotion: Bool) -> Double {
        _ = phase
        return reduceMotion ? 0 : normalDuration
    }
}

/// A pinned game's row in `StorageView`'s protected section.
struct PinnedGameRow: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Shows the total cache size against quota and floor, the LRU-ordered
/// reclaim candidate list with per-game byte counts, the pinned set
/// marked as protected, unreferenced objects, quarantined partials, and
/// a plain statement that the server retains everything regardless of
/// what's reclaimed here. `.safeToEvict` (from `AvailabilityState`)
/// lives here and nowhere else — never a card badge.
struct StorageView: View {
    let totalUsedBytes: Int
    let quotaBytes: Int
    let floorBytes: Int
    let candidates: [EvictionCandidate]
    let pinnedGames: [PinnedGameRow]
    let unreferencedObjects: [UnreferencedObject]
    let quarantinedPartials: [QuarantinedPartial]
    let onReclaim: (Set<String>) -> Void
    let onRemoveQuarantined: (String) -> Void

    @State private var selected: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func formatBytes(_ bytes: Int) -> String {
        ByteFormatting.formatBytes(bytes)
    }

    /// A cache-object digest is evidence, not a useful 64-character visual
    /// label. Keep both ends visible for recognition while exposing the exact
    /// digest through accessibility below.
    static func displayDigest(_ sha256: String) -> String {
        guard sha256.count > 17 else { return sha256 }
        return "\(sha256.prefix(8))…\(sha256.suffix(8))"
    }

    /// The plain statement that reclaiming here never touches the
    /// server's copy — always rendered, regardless of candidate count.
    static let serverRetainsStatement = "The server keeps everything, no matter what you reclaim here."

    /// A calm, no-op message for reclaiming zero selected games — pure,
    /// so it's testable without hosting the view.
    static let reclaimingZeroMessage = "Nothing selected — nothing changed."

    enum Automation {
        static let root = "playstead.storage.inventory"
        static let state = "playstead.storage.state"
        static let selection = "playstead.storage.selection"
        static let reclaim = "playstead.storage.reclaim"

        static func candidate(_ slot: Int) -> String { "playstead.storage.candidate.\(slot)" }
        static func candidateToggle(_ slot: Int) -> String { "\(candidate(slot)).toggle" }
        static func pinned(_ slot: Int) -> String { "playstead.storage.pinned.\(slot)" }
        static func unreferenced(_ slot: Int) -> String { "playstead.storage.unreferenced.\(slot)" }
        static func quarantined(_ slot: Int) -> String { "playstead.storage.quarantined.\(slot)" }
        static func removeQuarantined(_ slot: Int) -> String { "\(quarantined(slot)).remove" }
    }

    private var stateValue: String {
        "used=\(totalUsedBytes);candidate-count=\(candidates.count);pinned-count=\(pinnedGames.count);unreferenced-count=\(unreferencedObjects.count);quarantined-count=\(quarantinedPartials.count)"
    }

    private var selectedBytes: Int {
        candidates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Storage")
                    .font(.psHeading)
                    .foregroundStyle(.primary)
                Text("\(Self.formatBytes(totalUsedBytes)) used of \(Self.formatBytes(quotaBytes)) quota — \(Self.formatBytes(floorBytes)) always kept free")
                    .font(.psBody)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Storage inventory state")
                    .accessibilityValue(stateValue)
                    .accessibilityIdentifier(Automation.state)
                Text(Self.serverRetainsStatement)
                    .font(.psLabel)
                    .foregroundStyle(.secondary)
            }

            if !pinnedGames.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Protected (pinned)")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(.primary)
                    ForEach(Array(pinnedGames.enumerated()), id: \.element.id) { slot, game in
                        Text(game.title)
                            .font(.psLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(game.title), protected from reclaim")
                            .accessibilityIdentifier(Automation.pinned(slot))
                    }
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Safe to remove")
                    .font(.psLabelEmphasized)
                    .foregroundStyle(.primary)
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
                            .accessibilityLabel("\(candidate.title) can be removed to free up space — it will stay on your server.")
                            .accessibilityValue("bytes=\(candidate.bytes);selected=\(selected.contains(candidate.id))")
                            .accessibilityIdentifier(Automation.candidate(slot))
                            .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
                            Divider()
                        }
                    }
                }
                Text("\(selected.count) selected — \(Self.formatBytes(selectedBytes))")
                    .font(.psLabel)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Storage reclaim selection")
                    .accessibilityValue("count=\(selected.count);bytes=\(selectedBytes)")
                    .accessibilityIdentifier(Automation.selection)
                Button("Reclaim selected") {
                    let selection = selected
                    selected.removeAll()
                    onReclaim(selection)
                }
                .disabled(selected.isEmpty)
                .playsteadFocusable(identifier: Automation.reclaim)
            }

            if !unreferencedObjects.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Unreferenced")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(.primary)
                    ForEach(Array(unreferencedObjects.enumerated()), id: \.element.id) { slot, object in
                        HStack {
                            Text(Self.displayDigest(object.sha256))
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(Self.formatBytes(object.bytes))
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Unreferenced cache object")
                        .accessibilityValue("sha256=\(object.sha256);bytes=\(object.bytes)")
                        .accessibilityIdentifier(Automation.unreferenced(slot))
                    }
                }
            }

            if !quarantinedPartials.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Quarantined partials")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(.primary)
                    ForEach(Array(quarantinedPartials.enumerated()), id: \.element.id) { slot, partial in
                        HStack {
                            Text((partial.path as NSString).lastPathComponent)
                            Spacer()
                            Text(Self.formatBytes(partial.bytes))
                            Button("Remove") { onRemoveQuarantined(partial.path) }
                                .playsteadFocusable(identifier: Automation.removeQuarantined(slot))
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(Automation.quarantined(slot))
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage inventory")
        .accessibilityIdentifier(Automation.root)
        .animation(
            .easeInOut(duration: StorageMotionContract.duration(for: .eviction, reduceMotion: reduceMotion)),
            value: candidates.count
        )
        .animation(
            .easeInOut(duration: StorageMotionContract.duration(for: .eviction, reduceMotion: reduceMotion)),
            value: totalUsedBytes
        )
    }
}
