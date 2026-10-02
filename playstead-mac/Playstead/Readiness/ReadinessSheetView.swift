import SwiftUI

/// A focused status-and-fix surface for one title, with its readiness
/// report and the relevant BIOS/controller state visible inline.
///
/// The row owns the primary Play action. This sheet explains any blocker,
/// offers its remedy, and lets the user inspect launch-related setup.
struct ReadinessSheetView: View {
    let entry: CatalogueEntry
    let report: ReadinessReport
    /// Re-runs the readiness evaluation after a remedy was acted on.
    var onRefresh: () -> Void = {}
    var onDownload: () -> Void = {}
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
    @State private var showsSaveHistory = false
    @State private var showsControllerTest = false
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

    private var systemDisplayName: String {
        LibraryViewModel.isUnidentified(entry)
            ? "Unknown system"
            : SystemRegistry.entry(for: entry.system).displayName
    }

    private var hasBIOSIssue: Bool {
        report.checks.contains { $0.kind == .bios && $0.outcome.isIssue }
    }

    private var hasControllerIssue: Bool {
        report.checks.contains { $0.kind == .controllerAndInput && $0.outcome.isIssue }
    }

    private var showsControllerSection: Bool {
        hasControllerIssue || !environment.controllerHost.connectedControllers.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Setup and save details stay in the focused, scrollable sheet;
            // the Done action remains visible while the content scrolls.
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text(entry.displayTitle)
                            .font(.psHeading)
                            .foregroundColor(DesignTokens.textPrimary)

                        ReadinessReportView(
                            report: report,
                            onRemedy: { apply($0, scrollProxy: scrollProxy) }
                        )

                        if let saveCheck = report.checks.first(where: { $0.kind == .saveState }),
                           !report.issueChecks.contains(where: { $0.kind == .saveState }) {
                            HealthySaveReadinessRow(check: saveCheck)
                        }

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

                        if hasBIOSIssue {
                            Divider()
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                Label("BIOS for \(systemDisplayName)", systemImage: "memorychip")
                                    .font(.psLabelEmphasized)
                                Text("BIOS files apply to all games on this system.")
                                    .font(.psLabel)
                                    .foregroundStyle(DesignTokens.textMuted)
                                BiosDropTargetView(
                                    target: BiosDropTarget(store: environment.biosStore, system: entry.system)
                                )
                            }
                            .id("readiness-bios")
                        }

                        if showsControllerSection {
                            Divider()
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                Label("Controller", systemImage: "gamecontroller")
                                    .font(.psLabelEmphasized)
                                Text("Controller mappings apply wherever you use this controller.")
                                    .font(.psLabel)
                                    .foregroundStyle(DesignTokens.textMuted)
                                ControllerSettingsView(
                                    connectedControllers: environment.controllerHost.connectedControllers,
                                    assignedControllerID: environment.controllerHost.assignedControllerID,
                                    mapping: environment.controllerMappingStore.mapping(
                                        forControllerProductID: environment.controllerHost.assignedControllerID ?? ""
                                    ),
                                    onAssign: { environment.controllerHost.assign(controllerID: $0) },
                                    onOpenTestView: { showsControllerTest = true }
                                )
                            }
                            .id("readiness-controls")
                        }

                        if showsAdapterSetup {
                            Divider()
                            AdapterSetupView()
                                .frame(minHeight: 220)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("playstead.readiness.content")
            }

            // The dismissal control must remain reachable while a remedy is
            // expanded, rather than becoming another off-screen target.
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
        .frame(minWidth: 520, idealHeight: 620, maxHeight: 720)
        .background(DesignTokens.background.ignoresSafeArea())
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
        .sheet(isPresented: $showsControllerTest) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack {
                    Text("Controller test").font(.psHeading)
                    Spacer()
                    Button("Done") { showsControllerTest = false }
                }
                if let descriptor = environment.controllerHost.connectedControllers.first(where: {
                    $0.id == environment.controllerHost.assignedControllerID
                }) {
                    ControllerTestView(
                        controllerName: descriptor.name,
                        availableInputs: descriptor.availableInputs,
                        liveInputs: environment.controllerHost.liveInputs
                    )
                } else {
                    Text("No active controller is connected.")
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(minWidth: 440, minHeight: 300)
            .background(DesignTokens.background.ignoresSafeArea())
        }
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
    private func apply(_ remedy: Remedy, scrollProxy: ScrollViewProxy) {
        switch remedy.action {
        case .installAdapter:
            showsAdapterSetup = true
        case .openBiosDropTarget:
            scrollProxy.scrollTo("readiness-bios", anchor: .top)
        case .openInputSettings:
            scrollProxy.scrollTo("readiness-controls", anchor: .top)
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

/// Healthy save state is still important readiness information: keep it
/// visible even though the general report lists only warnings and blockers.
private struct HealthySaveReadinessRow: View {
    let check: ReadinessCheck

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(StatusToken.verified)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ReadinessCheckKind.saveState.displayName)
                    .font(.psLabelEmphasized)
                    .foregroundColor(DesignTokens.textPrimary)
                Text(check.finding)
                    .font(.psLabel)
                    .foregroundColor(DesignTokens.textMuted)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ReadinessCheckKind.saveState.displayName). \(check.finding)")
        .accessibilityIdentifier("playstead.readiness.row.saveState")
    }
}
