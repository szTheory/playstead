import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The adapter surface: what the app can honestly say about the pinned
/// adapter, what state its installation is actually in, and the two ways
/// a user can get one — install the pinned release, or point at an
/// application bundle they already have.
///
/// This view exists because `AdapterInstaller` had no production call
/// site at all: it was referenced only from its own test file, so
/// `AdapterHost`'s install state was permanently `.notInstalled` and no
/// user of the shipped app could ever install the emulator. Everything
/// here goes through `AppEnvironment`'s shared installer and host — the
/// same instances readiness and launch consult — so a successful install
/// is immediately visible to the Play path, not just to this screen.
struct AdapterSetupView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Presents an `NSOpenPanel` and returns the application bundle the
    /// user picked, or `nil` on cancel. Injectable so a test exercises
    /// the selection path with no real panel — the same discipline
    /// `BiosDropTargetView.chooseFile` uses.
    var chooseApplication: () -> URL? = AdapterSetupView.defaultChooseApplication

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                if let card = environment.adapterCapabilityCard {
                    AdapterCapabilityCardView(card: card)
                } else {
                    Text("This build has no pinned adapter, so nothing can be installed.")
                        .font(.psBody)
                        .foregroundColor(DesignTokens.textPrimary)
                }

                statusLine

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button(Self.installActionTitle(for: environment.adapterInstallState)) {
                        Task { await environment.installAdapter() }
                    }
                    .disabled(environment.adapterSetupPhase == .installing || environment.adapterCatalog == nil)
                    .accessibilityLabel(Self.installActionTitle(for: environment.adapterInstallState))

                    Button("Choose an installed application…") {
                        guard let url = chooseApplication() else { return }
                        Task { await environment.selectExistingAdapter(appURL: url) }
                    }
                    .disabled(environment.adapterSetupPhase == .installing || environment.adapterCatalog == nil)
                    .accessibilityLabel("Choose an adapter application already installed on this Mac")
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let text = Self.statusText(
            phase: environment.adapterSetupPhase, installState: environment.adapterInstallState
        )
        HStack(spacing: DesignTokens.Spacing.sm) {
            if environment.adapterSetupPhase == .installing {
                ProgressView().controlSize(.small)
            }
            Text(text)
                .font(.psLabelEmphasized)
                .foregroundColor(Self.isFailure(environment.adapterSetupPhase) ? StatusToken.missingDependency : DesignTokens.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    // MARK: - Pure presentation (asserted directly by tests)

    /// The four states this surface has to distinguish, in plain words:
    /// not installed, installing, installed and verified, and failed with
    /// the actual reason it failed.
    static func statusText(phase: AdapterSetupPhase, installState: AdapterInstallState) -> String {
        switch phase {
        case .installing:
            return "Installing the pinned adapter…"
        case .failed(let reason):
            return reason
        case .idle:
            switch installState {
            case .notInstalled:
                return "Not installed. Install the pinned adapter, or choose one already on this Mac."
            case .installed(let path, let verified):
                return verified
                    ? "Installed at \(path). Its program file is re-checked against its recorded digest on every launch."
                    : "Installed at \(path), but with no recorded digest to re-check. Launch will refuse it until it is reinstalled."
            }
        }
    }

    static func installActionTitle(for installState: AdapterInstallState) -> String {
        if case .installed = installState { return "Reinstall the pinned adapter" }
        return "Install the pinned adapter"
    }

    private static func isFailure(_ phase: AdapterSetupPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    static func defaultChooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
