import SwiftUI

/// A quiet, non-modal notice shown when the assigned controller
/// disconnects — names the controller and what to do, never opens a
/// sheet or alert, and never disables anything else on screen. A user
/// whose controller battery dies mid-navigation must never be trapped:
/// every other control on the surface behind this banner stays exactly
/// as operable by keyboard and pointer as it was before the
/// disconnect (D-14).
struct ControllerRecoveryBanner: View {
    let controllerName: String
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "gamecontroller.slash")
                .foregroundStyle(StatusToken.attention)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(controllerName) disconnected")
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Keyboard and pointer still work everywhere. Reconnect it, or pick a different controller in Settings.")
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            }
            Spacer()
            Button("Dismiss", action: onDismiss)
                .accessibilityLabel("Dismiss controller disconnected notice")
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
        .background(DesignTokens.border.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(controllerName) disconnected. Keyboard and pointer still work everywhere.")
    }
}
