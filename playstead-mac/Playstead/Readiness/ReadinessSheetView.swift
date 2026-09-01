import SwiftUI

/// The surface a blocked Play lands on: the real `ReadinessReport` for
/// one title, and — inline, at the moment it becomes relevant — the
/// surface each blocking remedy points at.
///
/// `ReadinessReportView` and `ReadinessEngine` were both instantiated
/// only in tests before this; the shipped Play path checked only whether
/// the required members happened to be cached and then failed with an
/// untyped `"Launch failed: …"` string. This view is where a blocking
/// condition becomes something the user can act on instead.
struct ReadinessSheetView: View {
    let entry: CatalogueEntry
    let report: ReadinessReport
    /// Re-runs the readiness evaluation after a remedy was acted on.
    var onRefresh: () -> Void = {}
    var onDownload: () -> Void = {}
    var onPlay: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(AppEnvironment.self) private var environment
    @State private var showsAdapterSetup = false
    @State private var showsBiosDropTarget = false
    @State private var showsInputSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(entry.displayTitle)
                .font(.psHeading)
                .foregroundColor(DesignTokens.textPrimary)

            ReadinessReportView(report: report, onRemedy: apply, onPlay: onPlay)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button("BIOS settings") { showsBiosDropTarget = true }
                    .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.openBios)
                Button("Controller settings") { showsInputSettings = true }
                    .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.openControllerSettings)
            }

            if showsAdapterSetup {
                Divider()
                AdapterSetupView()
                    .frame(minHeight: 220)
            }
            if showsBiosDropTarget {
                Divider()
                BiosDropTargetView(target: BiosDropTarget(store: environment.biosStore, system: entry.system))
            }
            if showsInputSettings {
                Divider()
                ControllerSettingsView(
                    connectedControllers: environment.controllerHost.connectedControllers,
                    assignedControllerID: environment.controllerHost.assignedControllerID,
                    mapping: environment.controllerMappingStore.mapping(
                        forControllerProductID: environment.controllerHost.assignedControllerID ?? ""
                    ),
                    onAssign: { environment.controllerHost.assign(controllerID: $0) }
                )
            }

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .playsteadFocusable(identifier: AccessibilityIdentifiers.Control.done)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game readiness")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.readiness)
        .onExitCommand(perform: onClose)
    }

    /// Routes one remedy to the surface that can actually resolve it.
    /// Every branch either opens a real surface or performs a real
    /// action — a remedy button that did nothing would be worse than no
    /// button at all.
    private func apply(_ remedy: Remedy) {
        switch remedy.action {
        case .installAdapter:
            showsAdapterSetup = true
        case .openBiosDropTarget:
            showsBiosDropTarget = true
        case .openInputSettings:
            showsInputSettings = true
        case .downloadMember:
            onDownload()
        case .repairSaveDirectory:
            environment.repairSaveDirectory(for: entry)
            onRefresh()
        }
    }
}
