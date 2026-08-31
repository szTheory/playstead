import SwiftUI

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

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatBytes(_ bytes: Int) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    /// The plain statement that reclaiming here never touches the
    /// server's copy — always rendered, regardless of candidate count.
    static let serverRetainsStatement = "The server keeps everything, no matter what you reclaim here."

    /// A calm, no-op message for reclaiming zero selected games — pure,
    /// so it's testable without hosting the view.
    static let reclaimingZeroMessage = "Nothing selected — nothing changed."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Storage")
                    .font(.psHeading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("\(Self.formatBytes(totalUsedBytes)) used of \(Self.formatBytes(quotaBytes)) quota — \(Self.formatBytes(floorBytes)) always kept free")
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(Self.serverRetainsStatement)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            }

            if !pinnedGames.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Protected (pinned)")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(DesignTokens.textPrimary)
                    ForEach(pinnedGames) { game in
                        Text(game.title)
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Safe to remove")
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
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
                        .accessibilityLabel("\(candidate.title) can be removed to free up space — it will stay on your server.")
                    }
                    Button("Reclaim selected") { onReclaim(selected) }
                        .disabled(selected.isEmpty)
                }
            }

            if !unreferencedObjects.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Unreferenced")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(DesignTokens.textPrimary)
                    ForEach(unreferencedObjects) { object in
                        HStack {
                            Text(object.sha256)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(Self.formatBytes(object.bytes))
                        }
                        .foregroundStyle(DesignTokens.textMuted)
                    }
                }
            }

            if !quarantinedPartials.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Quarantined partials")
                        .font(.psLabelEmphasized)
                        .foregroundStyle(DesignTokens.textPrimary)
                    ForEach(quarantinedPartials) { partial in
                        HStack {
                            Text((partial.path as NSString).lastPathComponent)
                            Spacer()
                            Text(Self.formatBytes(partial.bytes))
                            Button("Remove") { onRemoveQuarantined(partial.path) }
                        }
                        .foregroundStyle(DesignTokens.textMuted)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
