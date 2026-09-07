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
    /// D-37: the Save row's "Review versions…" action -- navigational
    /// only, opens the per-game save history sheet inline below. Never
    /// invoked from a blocking outcome; the Save row can't produce one.
    var onReviewSaveVersions: () -> Void = {}
    /// The sessions `SaveHistorySheet` renders once opened -- a closure
    /// so this view stays fully testable without a live `SaveStore`
    /// dependency; defaults to empty (the "No saves yet." empty state).
    var saveHistorySessions: () -> [SaveHistorySession] = { [] }
    /// D-36's game-level rollup (plan 04-22, WINDOWS #47) rendered above
    /// `SaveHistorySheet`'s session list -- a closure for the same
    /// testability reason as `saveHistorySessions`; defaults to nil,
    /// which renders no summary line at all.
    var saveRollupSummary: () -> SaveRollupResult? = { nil }

    @Environment(AppEnvironment.self) private var environment
    @State private var showsAdapterSetup = false
    @State private var showsBiosDropTarget = false
    @State private var showsInputSettings = false
    @State private var showsSaveHistory = false
    /// MC-06: shown instead of `SaveHistorySheet` when "Review
    /// versions…" is reached for a genuinely diverged line — history and
    /// comparison are different questions ("what happened" vs. "which
    /// one do I keep"), and D-50 through D-55's comparison sheet is the
    /// one built to answer the second.
    @State private var showsConflictComparison = false
    @FocusState private var doneHasFocus: Bool

    /// MC-05: the escalated-tier panel for this game, or `nil` when
    /// nothing genuinely unfixable applies right now — computed fresh
    /// from `SaveStore`/`Reachability` on every render (D-21).
    private var onlyCopyEscalation: OnlyCopyEscalationResult? {
        let count = environment.onlyOnThisMacCount(forAssetSetID: entry.id)
        guard count > 0 else { return nil }
        return OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(
                onlyOnThisMacCount: count,
                title: entry.displayTitle,
                failureClassification: environment.saveUploadFailureClassification()
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(entry.displayTitle)
                .font(.psHeading)
                .foregroundColor(DesignTokens.textPrimary)

            ReadinessReportView(report: report, onRemedy: apply, onPlay: onPlay)

            if let onlyCopyEscalation {
                OnlyCopyEscalationPanel(
                    escalation: onlyCopyEscalation,
                    onFix: { onRefresh() },
                    onExport: {
                        Task { await environment.openConsoleSavesExport(forAssetSetIDs: [entry.id]) }
                    },
                    onWhatsStoredWhere: { showsSaveHistory = true }
                )
            }

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
            if showsSaveHistory {
                Divider()
                SaveHistorySheet(
                    title: entry.displayTitle,
                    sessions: saveHistorySessions(),
                    summary: saveRollupSummary(),
                    onClose: { showsSaveHistory = false }
                )
            }
            if showsConflictComparison {
                Divider()
                ConflictComparisonSheet(
                    title: entry.displayTitle,
                    sides: environment.conflictSides(forAssetSetID: entry.id),
                    thisDeviceOrigin: Self.thisDeviceOrigin,
                    onChoose: { chosenRevisionID in
                        environment.resolveSaveDivergence(assetSetID: entry.id, chosenRevisionID: chosenRevisionID)
                        showsConflictComparison = false
                        onRefresh()
                    },
                    onExport: { _ in
                        Task { await environment.openConsoleSavesExport(forAssetSetIDs: [entry.id]) }
                    },
                    onKeepBoth: {
                        environment.acknowledgeSaveDivergence(assetSetID: entry.id, thisDeviceOrigin: Self.thisDeviceOrigin)
                        showsConflictComparison = false
                        onRefresh()
                    },
                    onClose: { showsConflictComparison = false }
                )
            }

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .focused($doneHasFocus)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Control.done)
                    .overlay {
                        RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                            .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                            .opacity(PlaysteadFocusRing.opacity(isFocused: doneHasFocus))
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 520)
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game readiness")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.readiness)
        .focusSection()
        .defaultFocus($doneHasFocus, true)
        // `.defaultFocus` alone is not observed to place focus in this app when
        // the view arrives through `.sheet` -- that window is not yet key when
        // `onAppear` runs, so the focus is discarded. Hop one runloop first:
        // the one focus-placement pattern here observed to work in CI, proved
        // under G-04-8 on `OnlyCopyInterruptiveSheet` and swept to every other
        // `.defaultFocus` sheet by `sheet-focus-placement-test.sh`.
        .onAppear { placeInitialFocus() }
        .onExitCommand(perform: onClose)
    }

    /// The dismissal control owns focus the moment this sheet appears, so a
    /// keyboard user always has a defined starting point and a visible ring.
    private func placeInitialFocus() {
        Task { @MainActor in
            await Task.yield()
            doneHasFocus = true
        }
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
        case .reviewSaveVersions:
            // MC-06: a genuine, undisposed fork opens the comparison
            // sheet D-50 through D-55 built to resolve exactly this —
            // never `SaveHistorySheet`, which answers a different
            // question ("what happened", not "which one do I keep").
            if environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id) {
                showsConflictComparison = true
            } else {
                showsSaveHistory = true
            }
            onReviewSaveVersions()
        }
    }

    /// This device's display name for `ConflictComparisonSheet`'s
    /// "Keep both" explainer and `SaveConflictResolver`'s resolution
    /// result — no device-name registry exists on this client yet
    /// (`LaunchSaveContextBuilder` falls back to the raw device id for
    /// the same reason), so this mirrors the literal placeholder this
    /// file family's own UI-testing harness already uses.
    private static let thisDeviceOrigin = SaveOriginNames.thisDevice
}
