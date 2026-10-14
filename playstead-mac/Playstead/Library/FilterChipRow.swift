import SwiftUI

struct FilterChip: Identifiable, Hashable {
    let id: String
    let label: String
}

/// System/availability filters — also the controller path to narrowing a
/// library when text entry is unavailable. Selected and controller-focused
/// states are separate, so focus never changes a filter by itself.
struct FilterChipRow: View {
    let chips: [FilterChip]
    let selectedIDs: Set<String>
    let controllerFocusedID: String?
    let onToggle: (String) -> Void

    init(
        chips: [FilterChip],
        selectedIDs: Set<String>,
        controllerFocusedID: String? = nil,
        onToggle: @escaping (String) -> Void
    ) {
        self.chips = chips
        self.selectedIDs = selectedIDs
        self.controllerFocusedID = controllerFocusedID
        self.onToggle = onToggle
    }

    /// Kept for static snapshot fixtures that model a single selected chip.
    init(chips: [FilterChip], selectedID: String?, onSelect: @escaping (String?) -> Void) {
        self.init(
            chips: chips,
            selectedIDs: selectedID.map { [$0] } ?? [],
            onToggle: { onSelect($0) }
        )
    }

    static func isSelected(_ chip: FilterChip, selectedIDs: Set<String>) -> Bool {
        selectedIDs.contains(chip.id)
    }

    static func isSelected(_ chip: FilterChip, selectedID: String?) -> Bool {
        chip.id == selectedID
    }

    static func accessibilityIdentifier(for chipID: String) -> String {
        "library.filter.\(chipID)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(chips) { chip in
                        chipButton(chip)
                            .id(chip.id)
                    }
                }
            }
            .onChange(of: controllerFocusedID) { _, focusedID in
                guard let focusedID else { return }
                proxy.scrollTo(focusedID, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library filters")
    }

    private func chipButton(_ chip: FilterChip) -> some View {
        let isSelected = Self.isSelected(chip, selectedIDs: selectedIDs)
        let isControllerFocused = controllerFocusedID == chip.id
        return Button {
            onToggle(chip.id)
        } label: {
            Text(chip.label)
                .font(.psLabel)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
                .background {
                    Capsule().fill(
                        isControllerFocused
                            ? DesignTokens.focusRing.opacity(0.24)
                            : isSelected
                                ? DesignTokens.focusRing.opacity(0.16)
                                : DesignTokens.border.opacity(0.3)
                    )
                }
                .overlay {
                    if isControllerFocused {
                        Capsule().stroke(DesignTokens.focusRing, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(chip.label)
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: chip.id))
    }
}
