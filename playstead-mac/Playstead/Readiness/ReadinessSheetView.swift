import SwiftUI

/// A failed local save choice keeps the comparison open for retry. A receipt,
/// including an idempotent no-op, is required before the caller dismisses it.
struct SaveConflictChoiceFeedback {
    private(set) var errorMessage: String?

    mutating func attempt(_ resolve: () -> SaveConflictResolution?) -> Bool {
        guard resolve() != nil else {
            errorMessage = "Couldn't save this choice. Try again."
            return false
        }
        errorMessage = nil
        return true
    }
}

/// A focused status-and-fix surface for one title, with its readiness
/// report and explicit destinations for BIOS, controllers and saves.
///
/// The row owns the primary Play action. This sheet explains any blocker,
/// offers its remedy, and lets the user inspect launch-related setup.
struct ReadinessSheetView: View {
    let entry: CatalogueEntry
    let report: ReadinessReport
    var isCheckingReadiness = false
    var onContinueReadinessForTest: (() -> Void)?
    /// Re-runs the readiness evaluation after a remedy was acted on.
    var onRefresh: () -> Void = {}
    var onDownload: () -> Void = {}
    var onClose: () -> Void = {}
    /// D-37: the Save row's "Review versions…" action -- navigational
    /// only, opens the per-game save history destination. Never
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
    @State private var destination: Destination = .overview
    /// MC-06: shown instead of `SaveHistorySheet` when "Review
    /// versions…" is reached for a genuinely diverged line — history and
    /// comparison are different questions ("what happened" vs. "which
    /// one do I keep"), and D-50 through D-55's comparison sheet is the
    /// one built to answer the second.
    @State private var conflictFeedback = SaveConflictChoiceFeedback()
    @FocusState private var doneHasFocus: Bool
    @FocusState private var backHasFocus: Bool

    /// UI_TESTING can constrain the production view to its approved history
    /// minimum without adding a second view implementation or changing the
    /// release layout. The normal readiness surface remains 720×520 points.
    private var presentationSize: CGSize {
#if UI_TESTING
        if ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_WINDOW_SIZE"] == "480x360" {
            return CGSize(width: 480, height: 360)
        }
#endif
        return CGSize(width: 720, height: 520)
    }

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
        hasControllerIssue
            || !environment.controllerHost.connectedControllers.isEmpty
            // Keep the recovery route available after keyboard/pointer
            // fallback makes the readiness check healthy, and after the
            // banner itself has been dismissed.
            || (
                environment.controllerHost.connectionState == .disconnected
                    && environment.controllerHost.lastDisconnectedControllerName != nil
            )
    }

    private enum Destination: Equatable {
        case overview, bios, controllers, controllerTest, saveHistory, conflict

        var ownsFocus: Bool { self == .saveHistory || self == .conflict }
    }

    var body: some View {
        Group {
            if destination.ownsFocus {
                destinationContent
            } else {
                navigationContent
            }
        }
        .frame(width: presentationSize.width, height: presentationSize.height)
        .background(DesignTokens.background.ignoresSafeArea())
        .onAppear { placeInitialFocus() }
        .onChange(of: destination) { _, _ in placeInitialFocus() }
        .onExitCommand {
            if destination == .overview { onClose() } else { goBack() }
        }
        .sheet(isPresented: $showsAdapterSetup, onDismiss: {
            onRefresh()
            doneHasFocus = false
            placeInitialFocus()
        }) {
            ReadinessAdapterSetupSheet(onClose: { showsAdapterSetup = false })
                .environment(environment)
        }
    }

    private var navigationContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationContent
            if !destination.ownsFocus {
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
                .padding(DesignTokens.Spacing.lg)
            }
        }
        .frame(width: presentationSize.width, height: presentationSize.height)
        .background(DesignTokens.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game readiness")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.readiness)
        .focusSection()
        .defaultFocus($doneHasFocus, true)
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .overview:
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text(entry.displayTitle)
                        .font(.psHeading)
                        .foregroundStyle(DesignTokens.textPrimary)
                    if isCheckingReadiness {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            ProgressView().controlSize(.small)
                            Text("Checking readiness")
                                .font(.psLabel)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("playstead.readiness.checking")
#if UI_TESTING
                        if UITestBootstrap.isRequested(), let onContinueReadinessForTest {
                            Button("Continue check", action: onContinueReadinessForTest)
                                .accessibilityIdentifier("playstead.test.readiness.release-sheet")
                        }
#endif
                    }
                    ReadinessReportView(report: report, onRemedy: apply)
                    if let saveCheck = report.checks.first(where: { $0.kind == .saveState }),
                       !report.issueChecks.contains(where: { $0.kind == .saveState }) {
                        HealthySaveReadinessRow(check: saveCheck, onViewHistory: openSaveHistory)
                    }
                    if let onlyCopyEscalation {
                        OnlyCopyEscalationPanel(
                            escalation: onlyCopyEscalation,
                            onFix: { onRefresh() },
                            onExport: {
                                Task { await environment.openConsoleSavesExport(forAssetSetIDs: [entry.id]) }
                            },
                            onWhatsStoredWhere: openSaveHistory
                        )
                    }
                    if hasBIOSIssue {
                        Button("BIOS for \(systemDisplayName)…") { destination = .bios }
                            .accessibilityIdentifier("playstead.readiness.open-bios")
                    }
                    if showsControllerSection {
                        Button("Controller settings…") { destination = .controllers }
                            .accessibilityIdentifier(AccessibilityIdentifiers.Control.openControllerSettings)
                    }
                }
                .padding(DesignTokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("playstead.readiness.content")
        case .bios, .controllers, .controllerTest:
            destinationHeader
            ScrollView {
                Group {
                    switch destination {
                    case .bios:
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("BIOS files apply to all games on this system.")
                                .font(.psLabel)
                                .foregroundStyle(DesignTokens.textMuted)
                            BiosDropTargetView(
                                target: BiosDropTarget(store: environment.biosStore, system: entry.system)
                            )
                        }
                    case .controllers:
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("mGBA uses its own controller bindings for gameplay.")
                                .font(.psLabel)
                                .foregroundStyle(DesignTokens.textMuted)
                            ControllerSettingsView(
                                connectedControllers: environment.controllerHost.connectedControllers,
                                assignedControllerID: environment.controllerHost.assignedControllerID,
                                mapping: environment.controllerMapping(for: environment.controllerHost.assignedControllerID),
                                mappingError: environment.controllerMappingError,
                                liveInputs: environment.controllerHost.liveInputs,
                                showsMappingControls: environment.showsSimulatedControllerMappingControls,
                                onAssign: { _ = environment.assignController($0) },
                                onRemap: { input, target in _ = environment.remapActiveController(adapterInput: input, to: target) },
                                onReset: { _ = environment.resetActiveControllerMapping() },
                                onOpenTestView: { destination = .controllerTest }
                            )
                        }
                    case .controllerTest:
                        controllerTestSection
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("playstead.readiness.content")
        case .saveHistory:
            SaveHistorySheet(
                title: entry.displayTitle,
                sessions: saveHistorySessions(),
                summary: saveRollupSummary(),
                onClose: { destination = .overview }
            )
        case .conflict:
            ConflictComparisonSheet(
                title: entry.displayTitle,
                sides: environment.conflictSides(forAssetSetID: entry.id),
                thisDeviceOrigin: Self.thisDeviceOrigin,
                resultMessage: conflictFeedback.errorMessage,
                onChoose: { chosenRevisionID in
                    guard conflictFeedback.attempt({
                        environment.resolveSaveDivergence(assetSetID: entry.id, chosenRevisionID: chosenRevisionID)
                    }) else { return }
                    destination = .overview
                    onRefresh()
                },
                onExport: { _ in
                    Task { await environment.openConsoleSavesExport(forAssetSetIDs: [entry.id]) }
                },
                onKeepBoth: {
                    guard conflictFeedback.attempt({
                        environment.acknowledgeSaveDivergence(assetSetID: entry.id, thisDeviceOrigin: Self.thisDeviceOrigin)
                    }) else { return }
                    destination = .overview
                    onRefresh()
                },
                onClose: {
                    conflictFeedback = SaveConflictChoiceFeedback()
                    destination = .overview
                }
            )
        }
    }

    private var destinationHeader: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(destination == .bios ? "BIOS for \(systemDisplayName)" : destination == .controllers ? "Controller settings" : "Controller test")
                .font(.psHeading)
            Spacer()
            Button(destination == .controllerTest ? "Back to controller settings" : "Back to readiness", action: goBack)
                .focused($backHasFocus)
                .accessibilityIdentifier(destination == .controllerTest ? "playstead.controller.test.done" : "playstead.readiness.destination.back")
                .overlay {
                    RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                        .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                        .opacity(PlaysteadFocusRing.opacity(isFocused: backHasFocus))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
        }
        .padding(DesignTokens.Spacing.lg)
    }

    private func goBack() {
        destination = destination == .controllerTest ? .controllers : .overview
    }

    private func openSaveHistory() {
        destination = .saveHistory
        onReviewSaveVersions()
    }

    @ViewBuilder
    private var controllerTestSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let descriptor = environment.controllerHost.connectedControllers.first(where: {
                $0.id == environment.controllerHost.assignedControllerID
            }) {
#if UI_TESTING
                ControllerTestView(
                    controllerName: descriptor.name,
                    availableInputs: descriptor.availableInputs,
                    liveInputs: environment.controllerHost.liveInputs,
                    buttonStyle: descriptor.buttonStyle ?? .generic,
                    onPressA: environment.uiTestControllerInputDriver.map { driver in { driver.pressA() } },
                    onReleaseA: environment.uiTestControllerInputDriver.map { driver in { driver.releaseA() } },
                    onDisconnect: environment.uiTestControllerInputDriver.map { driver in { driver.disconnect() } }
                )
#else
                ControllerTestView(
                    controllerName: descriptor.name,
                    availableInputs: descriptor.availableInputs,
                    liveInputs: environment.controllerHost.liveInputs,
                    buttonStyle: descriptor.buttonStyle ?? .generic
                )
#endif
            } else {
                Text("No active controller is connected.")
                    .foregroundStyle(DesignTokens.textMuted)
#if UI_TESTING
                if let driver = environment.uiTestControllerInputDriver {
                    Button("Reconnect") { driver.reconnect() }
                        .accessibilityIdentifier("playstead.controller.test.reconnect")
                }
#endif
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playstead.surface.controller-test")
        .id("readiness-controller-test")
    }

    /// Keep the established safe Done focus through readiness navigation.
    /// History/comparison manage their own dismissal focus.
    private func placeInitialFocus() {
        doneHasFocus = false
        backHasFocus = false
        guard !destination.ownsFocus else { return }
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
        case .installAdapter, .reviewAdapterSupport:
            showsAdapterSetup = true
        case .openBiosDropTarget:
            destination = .bios
        case .openInputSettings:
            destination = .controllers
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
                conflictFeedback = SaveConflictChoiceFeedback()
                destination = .conflict
            } else {
                destination = .saveHistory
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

/// Setup is a focused native subtask, rather than content inserted below
/// the readiness report. Header, escape path and adapter actions are pinned.
private struct ReadinessAdapterSetupSheet: View {
    let onClose: () -> Void
    @FocusState private var backHasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Adapter setup").font(.psHeading)
                Spacer()
                Button("Back to readiness", action: onClose)
                    .focused($backHasFocus)
                    .accessibilityIdentifier("playstead.readiness.adapter.back")
                    .overlay {
                        RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                            .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                            .opacity(PlaysteadFocusRing.opacity(isFocused: backHasFocus))
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
            }
            .padding(DesignTokens.Spacing.lg)

            AdapterSetupView()
        }
        .frame(width: 600, height: 480)
        .background(DesignTokens.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adapter setup from game readiness")
        .accessibilityIdentifier("playstead.surface.readiness-adapter-setup")
        .focusSection()
        .defaultFocus($backHasFocus, true)
        .onAppear { placeInitialFocus() }
        .onExitCommand(perform: onClose)
    }

    private func placeInitialFocus() {
        Task { @MainActor in
            await Task.yield()
            backHasFocus = true
        }
    }
}

/// Healthy save state is still important readiness information: keep it
/// visible even though the general report lists only warnings and blockers.
private struct HealthySaveReadinessRow: View {
    let check: ReadinessCheck
    var onViewHistory: () -> Void = {}

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(StatusToken.verified)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(ReadinessCheckKind.saveState.displayName)
                    .font(.psLabelEmphasized)
                    .foregroundColor(DesignTokens.textPrimary)
                Text(check.finding)
                    .font(.psLabel)
                    .foregroundColor(DesignTokens.textMuted)
            }
            Spacer()
            Button("Save history…", action: onViewHistory)
                .accessibilityIdentifier("playstead.readiness.open-save-history")
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ReadinessCheckKind.saveState.displayName). \(check.finding)")
        .accessibilityIdentifier("playstead.readiness.row.saveState")
    }
}
