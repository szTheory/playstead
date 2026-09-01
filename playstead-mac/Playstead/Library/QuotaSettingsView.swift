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

    enum Automation {
        static let root = "playstead.quota.root"
        static let state = "playstead.quota.state"
        static let increase = "playstead.quota.increase"
        static let decrease = "playstead.quota.decrease"
    }

    private var stateValue: String {
        "used=\(usedBytes);quota=\(policy.quotaBytes);floor=\(policy.floorBytes)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Storage")
                .font(.psHeading)
                .foregroundStyle(.primary)

            Text("\(Self.formatBytes(usedBytes)) used of \(Self.formatBytes(policy.quotaBytes)) quota")
                .font(.psBody)
                .foregroundStyle(.primary)
                .accessibilityLabel("Storage quota state")
                .accessibilityValue(stateValue)
                .accessibilityIdentifier(Automation.state)

            Text("Free-space floor: \(Self.formatBytes(policy.floorBytes)) always kept free")
                .font(.psLabel)
                .foregroundStyle(.secondary)

            Text(Self.floorPrecedenceStatement)
                .font(.psLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("Quota: \(Self.formatBytes(policy.quotaBytes))")
                    .font(.psLabelEmphasized)
                Button("Decrease quota") {
                    onSetQuota(max(0, policy.quotaBytes - QuotaPolicy.gibibyte))
                }
                .disabled(policy.quotaBytes == 0)
                .playsteadFocusable(identifier: Automation.decrease)
                Button("Increase quota") {
                    onSetQuota(policy.quotaBytes + QuotaPolicy.gibibyte)
                }
                .playsteadFocusable(identifier: Automation.increase)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quota settings")
        .accessibilityIdentifier(Automation.root)
    }
}
