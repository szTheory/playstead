import SwiftUI

/// Shown once, dismissibly, on a newly paired Mac whose catalogue is
/// already non-empty (03-UI-SPEC.md Copywriting Contract, D-15) —
/// explains that the library lives on the user's own server and that
/// nothing downloads automatically.
struct FirstRunBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Your library lives on your server.")
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Everything here is stored safely on your Playstead server. Download what you want to play offline.")
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
            }
            Spacer()
            Button("Dismiss", action: onDismiss)
                .accessibilityLabel("Dismiss the first-run banner")
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.border.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
