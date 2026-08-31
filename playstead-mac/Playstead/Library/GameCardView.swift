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
        let statusSentence = LibraryStatus.highestPriority(among: statuses)?.accessibleName(title: displayTitle) ?? ""
        return "\(displayTitle), \(systemName), \(statusSentence)"
    }
}
