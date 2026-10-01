import SwiftUI

/// Renders only warnings and blockers from a `ReadinessReport`, with the
/// available remedy. Healthy checks stay out of this issue-focused surface.
struct ReadinessReportView: View {
    let report: ReadinessReport
    var onRemedy: (Remedy) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(report.issueChecks, id: \.kind) { check in
                ReadinessRow(check: check, onRemedy: onRemedy)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }
}

private struct ReadinessRow: View {
    let check: ReadinessCheck
    let onRemedy: (Remedy) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: glyphName)
                .foregroundColor(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
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
