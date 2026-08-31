import SwiftUI

/// A landscape, fixed-size (280×158) library tile with exactly three
/// zones: a dominant two-line clamped title, a meta line (system
/// monogram + not-yet-identified badge), and one status slot
/// (03-UI-SPEC.md Spacing Scale, Typography, Status Vocabulary). No
/// cover image, no generated artwork, no title-derived color — an
/// honestly typographic surface reads as intentional (D-12).
struct GameCardView: View {
    let title: String
    let systemID: String
    let isUnidentified: Bool
    let statuses: [LibraryStatus]

    private var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(displayTitle)
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            HStack(spacing: DesignTokens.Spacing.xs) {
                SystemMonogramView(systemID: systemID)
                if isUnidentified {
                    Text("Not yet identified")
                        .font(.psLabel)
                        .foregroundStyle(DesignTokens.textMuted)
                }
                Spacer()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                StatusSlotView(statuses: statuses, title: displayTitle)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: DesignTokens.CardGeometry.width, height: DesignTokens.CardGeometry.height, alignment: .topLeading)
        .background(DesignTokens.border.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleLabel)
    }

    /// One accessible name combining title, system display name, and
    /// the status ladder's accessible-name sentence (03-UI-SPEC.md
    /// Accessibility Floor) — e.g. "Metroid Fusion, Game Boy Advance,
    /// downloaded and ready to play offline."
    var accessibleLabel: String {
        let systemName = SystemRegistry.entry(for: systemID).displayName
        guard let statusSentence = LibraryStatus.highestPriority(among: statuses)?.accessibleName(title: displayTitle) else {
            return "\(displayTitle), \(systemName)"
        }
        return "\(displayTitle), \(systemName), \(statusSentence)"
    }
}

// MARK: - AvailabilityState → LibraryStatus (plan 03-07)

extension LibraryStatus {
    /// Maps a read-time `AvailabilityState` (plus, when a member of this
    /// game is actively transferring, its progress percent) onto the
    /// card's status ladder — the determinate ring for the active member
    /// and the queued mark, sourced from `AvailabilityState` rather than
    /// any remembered/stored state (D-21).
    ///
    /// `.safeToEvict` has no card-ladder equivalent by construction: this
    /// function's caller MUST pass `AvailabilityState.derive(_:)`'s
    /// result (never `.deriveForStorageView(_:)`'s), and `derive(_:)`
    /// itself never returns `.safeToEvict` — the switch's `.safeToEvict`
    /// arm below is unreachable in practice and exists only so this
    /// mapping stays exhaustive over every `AvailabilityState` case.
    static func forCard(availability: AvailabilityState, activeMemberProgressPercent: Int?) -> LibraryStatus {
        switch availability {
        case .serverOnly:
            return .serverOnly
        case .queued:
            return .queued
        case .partial:
            if let activeMemberProgressPercent {
                return .downloading(percent: activeMemberProgressPercent)
            }
            return .queued
        case .verifiedLocal:
            return .verified
        case .pinnedOffline:
            return .pinned
        case .safeToEvict:
            return .serverOnly
        }
    }
}
