import SwiftUI

/// Shows every button and axis for the assigned controller live, so a
/// user confirms a mapping by pressing rather than by trusting a
/// label. Each row highlights the instant `ControllerHost.liveInputs`
/// contains its input name and returns to rest the instant it doesn't
/// — driven entirely by `ControllerHost`, so this view needs no
/// hardware access of its own.
struct ControllerTestView: View {
    let controllerName: String
    let availableInputs: [String]
    let liveInputs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Testing \(controllerName)")
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                ForEach(availableInputs, id: \.self) { input in
                    inputCell(for: input)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
    }

    private func inputCell(for input: String) -> some View {
        let isActive = liveInputs.contains(input)
        return Text(input)
            .font(.psLabel)
            .foregroundStyle(isActive ? Color.black : DesignTokens.textPrimary)
            .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
            .background(isActive ? StatusToken.verified : DesignTokens.border.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? Color.black : Color.clear, lineWidth: 2)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isActive ? "\(input), pressed" : "\(input), not pressed")
    }
}
