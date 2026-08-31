import SwiftUI

struct FilterChip: Identifiable, Hashable {
    let id: String
    let label: String
}

/// System/availability filter chips — the controller path to narrowing a
/// library (03-UI-SPEC.md Navigation & IA). A chip's pressed state is
/// expressed by shape and by an accessibility trait as well as by color,
/// never by color alone (QUAL-01).
struct FilterChipRow: View {
    let chips: [FilterChip]
    let selectedID: String?
    let onSelect: (String?) -> Void

    /// Whether `chip` is the currently pressed/selected chip — pure so
    /// `FilterTests` can assert the selection model directly, matching
    /// `StatusLadderTests`' precedent of testing logic, not rendered
    /// accessibility traits, in this headless-only test target.
    static func isSelected(_ chip: FilterChip, selectedID: String?) -> Bool {
        chip.id == selectedID
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
        }
    }

    private func chipButton(_ chip: FilterChip) -> some View {
        let isSelected = Self.isSelected(chip, selectedID: selectedID)
        return Button {
            onSelect(isSelected ? nil : chip.id)
        } label: {
            Text(chip.label)
                .font(.psLabel)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
                .background(isSelected ? DesignTokens.focusRing.opacity(0.25) : DesignTokens.border.opacity(0.3))
                .clipShape(isSelected ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(chip.label)
    }
}
