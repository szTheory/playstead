import SwiftUI

/// Renders only warnings and blockers from a `ReadinessReport`, with the
/// available remedy. Healthy checks stay out of this issue-focused surface.
struct ReadinessReportView: View {
    let report: ReadinessReport
    var onRemedy: (Remedy) -> Void = { _ in }
    private var visibleChecks: [ReadinessCheck] {
        report.checks.filter { $0.outcome.isIssue || ($0.kind == .systemSupport && !$0.details.isEmpty) }
    }

    static func boundedDiagnostic(_ value: String) -> String {
        guard value.count > 256 else { return value }
        return String(value.prefix(255)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(visibleChecks, id: \.kind) { check in
                ReadinessRow(check: check, onRemedy: onRemedy)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }
}

private struct ReadinessRow: View {
    let check: ReadinessCheck
    let onRemedy: (Remedy) -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: glyphName)
                    .foregroundColor(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(label)
                        .font(.psLabelEmphasized)
                        .foregroundColor(DesignTokens.textPrimary)
                    Text(check.finding)
                        .font(.psLabel)
                        .foregroundColor(DesignTokens.textMuted)
                }
                Spacer()
                if let remedy = check.remedy {
                    Button(remedy.title) { onRemedy(remedy) }
                        .accessibilityIdentifier("playstead.readiness.row.\(check.kind.rawValue).remedy")
                }
            }
            if !check.details.isEmpty {
                Button(showsDetails ? "Hide details" : "Details") {
                    showsDetails.toggle()
                }
                .accessibilityIdentifier("playstead.readiness.row.\(check.kind.rawValue).details")
                if showsDetails {
                    ForEach(Array(check.details.enumerated()), id: \.offset) { index, detail in
                        Text(verbatim: ReadinessReportView.boundedDiagnostic(detail))
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("playstead.readiness.row.\(check.kind.rawValue).detail.\(index)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label). \(check.finding)")
        .accessibilityIdentifier("playstead.readiness.row.\(check.kind.rawValue)")
    }

    private var glyphName: String {
        switch check.outcome {
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "wrench.and.screwdriver.fill"
        }
    }

    private var color: Color {
        switch check.outcome {
        case .ready: return StatusToken.verified
        case .warning: return StatusToken.attention
        case .blocked: return StatusToken.missingDependency
        }
    }

    private var label: String {
        check.kind.displayName
    }

}
