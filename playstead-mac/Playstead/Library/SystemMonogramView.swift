import SwiftUI

/// Renders a system's monogram tile (03-UI-SPEC.md Typography → System
/// monogram): Heading role at 600 weight, uppercase, 0.04em
/// letter-spacing, from the frozen `SystemRegistry` — never a
/// designer-chosen abbreviation.
struct SystemMonogramView: View {
    let systemID: String

    private var entry: SystemRegistry.Entry {
        SystemRegistry.entry(for: systemID)
    }

    var body: some View {
        Group {
            if entry.id == SystemRegistry.unknown.id {
                Image(systemName: "gamecontroller.fill")
                    .font(.psLabelEmphasized)
            } else {
                Text(entry.monogram)
                    .font(.psHeading)
                    .tracking(0.04 * 20)
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
        .background(SystemAccent.color(for: systemID))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.id == SystemRegistry.unknown.id ? "Unknown system" : entry.displayName)
    }
}
