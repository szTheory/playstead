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
    var isControllerFocused = false
    @FocusState private var dismissHasFocus: Bool
    var onDismiss: () -> Void = {}
    var onAccessibilityDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "gamecontroller.slash")
                .foregroundStyle(StatusToken.attention)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("\(controllerName) disconnected")
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Keyboard and pointer still work everywhere. Reconnect it, or pick a different controller in Settings.")
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            }
            Spacer()
            Button("Dismiss", action: onDismiss)
                .focused($dismissHasFocus)
                .accessibilityAction {
                    (onAccessibilityDismiss ?? onDismiss)()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                        .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                        .opacity(PlaysteadFocusRing.opacity(isFocused: isControllerFocused || dismissHasFocus))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .accessibilityValue(isControllerFocused ? "Controller focused" : "")
                .accessibilityLabel("Dismiss controller disconnected notice")
                .accessibilityIdentifier("playstead.controller.recovery-banner.dismiss")
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
        .background(DesignTokens.border.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(controllerName) disconnected. Keyboard and pointer still work everywhere.")
        .accessibilityIdentifier("playstead.controller.recovery-banner")
    }
}
