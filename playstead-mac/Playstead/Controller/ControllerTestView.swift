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
    var buttonStyle: ControllerButtonStyle = .generic
#if UI_TESTING
    var onPressA: (() -> Void)? = nil
    var onReleaseA: (() -> Void)? = nil
    var onDisconnect: (() -> Void)? = nil
#endif
    var onPressUp: (() -> Void)? = nil
    var onReleaseUp: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Testing \(controllerName)")
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)

            if buttonStyle != .generic {
                ControllerDiagram(style: buttonStyle, liveInputs: liveInputs, availableInputs: availableInputs)
            }
            Text("Press a button to see it light up.")
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)

#if UI_TESTING
            if let onPressA, let onReleaseA, let onDisconnect {
                HStack {
                    Button("Press A", action: onPressA)
                        .accessibilityIdentifier("playstead.controller.test.press-a")
                    Button("Release A", action: onReleaseA)
                        .accessibilityIdentifier("playstead.controller.test.release-a")
                    Button("Disconnect", action: onDisconnect)
                        .accessibilityIdentifier("playstead.controller.test.disconnect")
                }
            }
            if let onPressUp, let onReleaseUp {
                HStack {
                    Button("Press Up", action: onPressUp)
                        .accessibilityIdentifier("playstead.controller.test.press-up")
                    Button("Release Up", action: onReleaseUp)
                        .accessibilityIdentifier("playstead.controller.test.release-up")
                }
            }
#endif

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
        let label = ControllerInputLabel.displayName(for: input, style: buttonStyle)
        return Text("\(label)\n\(isActive ? "Pressed" : "Not pressed")")
            .font(.psLabel)
            .multilineTextAlignment(.center)
            .foregroundStyle(isActive ? Color.black : DesignTokens.textPrimary)
            .padding(DesignTokens.Spacing.xs)
            .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
            .background(isActive ? StatusToken.verified : DesignTokens.border.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.compact))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.compact)
                    .strokeBorder(isActive ? Color.black : Color.clear, lineWidth: 2)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isActive ? "\(label), pressed" : "\(label), not pressed")
            .accessibilityIdentifier("playstead.controller.input.\(input)")
    }
}
