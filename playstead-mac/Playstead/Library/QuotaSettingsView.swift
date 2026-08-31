import SwiftUI

/// Lets the user set the quota, shows current usage against both the
/// quota and the floor, and states plainly that the floor governs when
/// the two disagree (D-21). Pure/stateless — every value is a prop, so
/// this view (and its byte-formatting logic) is directly testable.
struct QuotaSettingsView: View {
    let policy: QuotaPolicy
    let usedBytes: Int
    let onSetQuota: (Int) -> Void

    static func formatBytes(_ bytes: Int) -> String {
        ByteFormatting.formatBytes(bytes)
    }

    /// The plain statement of precedence this view must always render —
    /// pulled into a pure function so a test can assert its content
    /// without hosting the view.
    static let floorPrecedenceStatement =
        "The free-space floor always takes priority. Even if you raise the quota, downloads still stop before your disk runs low."

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Storage")
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)

            Text("\(Self.formatBytes(usedBytes)) used of \(Self.formatBytes(policy.quotaBytes)) quota")
                .font(.psBody)
                .foregroundStyle(DesignTokens.textPrimary)

            Text("Free-space floor: \(Self.formatBytes(policy.floorBytes)) always kept free")
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)

            Text(Self.floorPrecedenceStatement)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)

            Stepper(
                "Quota: \(Self.formatBytes(policy.quotaBytes))",
                onIncrement: { onSetQuota(policy.quotaBytes + QuotaPolicy.gibibyte) },
                onDecrement: { onSetQuota(max(0, policy.quotaBytes - QuotaPolicy.gibibyte)) }
            )
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
