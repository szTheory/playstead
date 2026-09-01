import SwiftUI

/// Renders one `ReadinessReport`: one row per check, its outcome glyph
/// and text label, and its remedy button when blocking. Also where
/// adapter, BIOS, and controller settings surface — this is the moment
/// they're relevant (03-UI-SPEC.md's "Advanced settings placement").
/// Play becomes available only when the report has no blocking result.
struct ReadinessReportView: View {
    let report: ReadinessReport
    var onRemedy: (Remedy) -> Void = { _ in }
    var onPlay: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(report.checks, id: \.kind) { check in
                ReadinessRow(check: check, onRemedy: onRemedy)
            }

            Button(action: onPlay) {
                Text("Play")
            }
            .disabled(!report.isReady)
            .accessibilityLabel(report.isReady ? "Play" : "Play is unavailable until every readiness check passes.")
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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label). \(check.finding)")
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
        switch check.outcome {
        case .ready: return "Ready"
        case .warning(let text): return text
        case .blocked(let text): return text
        }
    }
}
