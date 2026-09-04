import SwiftUI

/// One side of a diverged save line's comparison, wholly caller-resolved
/// (mirrors `SaveHistorySession.deviceName`'s already-caller-supplied
/// precedent, and the console's `comparison_panel.ex` `side` map
/// one-for-one): this view never computes a relative time, a duration,
/// or resolves a device id to a name. `lastSaved` and
/// `playTimeSinceSplit` already carry their final, chosen-variant text
/// (e.g. the "no recorded play here" fallback) so this type stays a pure
/// renderer with zero ranking logic of its own.
struct ConflictSide: Identifiable, Equatable {
    let id: String
    let origin: String
    let lastSaved: String
    let playTimeSinceSplit: String
    let sinceSplitCount: Int
    let hasClockCaveat: Bool
    let isDownloaded: Bool
    let isChosen: Bool
    let digest: String
}

/// "Two versions of your progress" (D-50 through D-55): exactly four
/// facts per side, no ranking, full keyboard parity. Reachable from the
/// attention inbox and from game detail (never a modal, a notification,
/// or a launch prompt, D-53) -- this type is a plain, presentable
/// SwiftUI view with no presentation-trigger opinion of its own; the
/// caller decides how it is shown.
///
/// Recommends nothing: no side is highlighted, pre-selected, or
/// colour-distinguished, and there is no confirmation dialog before
/// choosing (D-51). This sheet never offers a way to reverse a choice
/// (D-49) -- the non-chosen side stays a live, permanently choosable
/// "Continue from this one" button instead. "Keep both" is a peer of the
/// choice buttons, never a secondary or dismissal action, and is never
/// re-raised for a disposed fork (D-52). Zero gesture-only, hover-only,
/// or pointer-only affordances; zero colour distinguishing the sides.
struct ConflictComparisonSheet: View {
    let title: String
    let sides: [ConflictSide]
    /// The origin this device is currently playing (independent of
    /// `ConflictSide.isChosen`, which only becomes true after an
    /// explicit resolution) -- used only by the "Keep both" explainer's
    /// "{Origin}" substitution.
    let thisDeviceOrigin: String
    var resultMessage: String?
    var onChoose: (String) -> Void = { _ in }
    var onExport: (String) -> Void = { _ in }
    var onKeepBoth: () -> Void = {}
    var onClose: () -> Void = {}

    @FocusState private var doneHasFocus: Bool

    enum Automation {
        static let surface = "playstead.surface.conflict-comparison"
        static let done = "playstead.conflict-comparison.done"
        static let keepBoth = "playstead.conflict-comparison.keep-both"
        static let result = "playstead.conflict-comparison.result"

        static func side(_ slot: Int) -> String { "playstead.conflict-comparison.side.\(slot)" }
        static func choose(_ slot: Int) -> String { "playstead.conflict-comparison.side.\(slot).choose" }
        static func chosen(_ slot: Int) -> String { "playstead.conflict-comparison.side.\(slot).chosen" }
        static func export(_ slot: Int) -> String { "playstead.conflict-comparison.side.\(slot).export" }
    }

    private var isPlural: Bool { sides.count > 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(SaveVocabulary.compareSheetTitle)
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)

            Text(subtitle)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)

            if let resultMessage {
                Text(resultMessage)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.border.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(Automation.result)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.md) {
                    ForEach(Array(sides.enumerated()), id: \.element.id) { slot, side in
                        ConflictSideView(gameTitle: title, side: side, slot: slot, onChoose: onChoose, onExport: onExport)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Button(isPlural ? SaveVocabulary.compareKeepBothActionPlural : SaveVocabulary.compareKeepBothAction, action: onKeepBoth)
                    .playsteadFocusable(identifier: Automation.keepBoth)
                Text(keepBothExplainer)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            }

            HStack {
                Spacer()
                Button(SaveVocabulary.compareDismiss, action: onClose)
                    .focused($doneHasFocus)
                    .accessibilityIdentifier(Automation.done)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 640, minHeight: 480)
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SaveVocabulary.compareSheetTitle)
        .accessibilityIdentifier(Automation.surface)
        .focusSection()
        .defaultFocus($doneHasFocus, true)
        .onExitCommand(perform: onClose)
    }

    private var subtitle: String {
        let template = isPlural ? SaveVocabulary.compareSubtitlePlural : SaveVocabulary.compareSubtitle
        return template
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{N}", with: "\(sides.count)")
    }

    private var keepBothExplainer: String {
        SaveVocabulary.compareKeepBothExplainer.replacingOccurrences(of: "{Origin}", with: thisDeviceOrigin)
    }
}

private struct ConflictSideView: View {
    let gameTitle: String
    let side: ConflictSide
    let slot: Int
    let onChoose: (String) -> Void
    let onExport: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(side.origin)
                .font(.psLabelEmphasized)
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityHidden(true)

            Text(side.lastSaved)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityHidden(true)

            Text(side.playTimeSinceSplit)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityHidden(true)

            Text(sinceSplitText)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityHidden(true)

            if side.hasClockCaveat {
                Text(clockCaveatText)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityHidden(true)
            }

            if !side.isDownloaded {
                Text(notDownloadedText)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityHidden(true)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                if side.isChosen {
                    Text(SaveVocabulary.compareChosenState)
                        .font(.psLabelEmphasized)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .accessibilityIdentifier(ConflictComparisonSheet.Automation.chosen(slot))
                } else {
                    Button(SaveVocabulary.compareChooseAction) { onChoose(side.id) }
                        .playsteadFocusable(identifier: ConflictComparisonSheet.Automation.choose(slot))
                }

                Button(SaveVocabulary.compareExportAction) { onExport(side.id) }
                    .playsteadFocusable(identifier: ConflictComparisonSheet.Automation.export(slot))
            }

            DisclosureGroup(SaveVocabulary.compareExpertDisclosure) {
                Text(side.digest)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("\(ConflictComparisonSheet.Automation.side(slot)).digest")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.border.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // `.contain`, not `.ignore`/`.combine`: the choose/export buttons
        // must stay individually reachable by keyboard/VoiceOver. The
        // label below is this side's one complete comparison sentence
        // (D-55) -- it describes the group node itself, it does not
        // replace or hide the buttons within it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibleSentence)
        .accessibilityIdentifier(ConflictComparisonSheet.Automation.side(slot))
    }

    private var sinceSplitText: String {
        side.sinceSplitCount == 1
            ? SaveVocabulary.compareSideLine3Singular
            : SaveVocabulary.compareSideLine3.replacingOccurrences(of: "{N}", with: "\(side.sinceSplitCount)")
    }

    private var clockCaveatText: String {
        SaveVocabulary.compareClockCaveat.replacingOccurrences(of: "{Origin}", with: side.origin)
    }

    private var notDownloadedText: String {
        SaveVocabulary.compareNotDownloaded.replacingOccurrences(of: "{title}", with: gameTitle)
    }

    /// One complete sentence combining every fact this side shows --
    /// D-55's "one accessibility element carrying one complete
    /// comparison sentence" requirement, mirrored from the console's own
    /// `accessible_sentence/1`.
    private var accessibleSentence: String {
        var sentence = "\(side.origin). \(side.lastSaved). \(side.playTimeSinceSplit). \(sinceSplitText)."
        if side.hasClockCaveat {
            sentence += " \(clockCaveatText)"
        }
        if !side.isDownloaded {
            sentence += " \(notDownloadedText)"
        }
        if side.isChosen {
            sentence += " \(SaveVocabulary.compareChosenState)."
        }
        return sentence
    }
}

#if UI_TESTING
/// A UI-testing-only harness presenting `ConflictComparisonSheet`
/// directly as the app's root view, driven by
/// `PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1` -- the same documented-seam
/// pattern `UITestBootstrap`'s save end-to-end hook uses (a UI test
/// target cannot `@testable import Playstead`, so a small, explicitly
/// test-only production seam is the accessible surface for a genuine,
/// real-window keyboard-interaction proof). No production navigation
/// reaches this sheet yet -- that live wiring (attention inbox, game
/// detail) is a later plan's job; this harness proves the sheet's own
/// keyboard operability end-to-end in a real hosted window with a fixed
/// synthetic two-side fork.
struct ConflictComparisonHarnessRootView: View {
    @State private var chosenID: String?
    @State private var keptBoth = false

    private static let baseSides: [ConflictSide] = [
        ConflictSide(
            id: "r1", origin: "This Mac", lastSaved: "Last saved 2 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 3,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "abc123"
        ),
        ConflictSide(
            id: "r2", origin: "Living Room Mac", lastSaved: "Last saved 3 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 1,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "def456"
        )
    ]

    var body: some View {
        ConflictComparisonSheet(
            title: "Metroid Fusion",
            sides: Self.baseSides.map { side in
                ConflictSide(
                    id: side.id, origin: side.origin, lastSaved: side.lastSaved,
                    playTimeSinceSplit: side.playTimeSinceSplit, sinceSplitCount: side.sinceSplitCount,
                    hasClockCaveat: side.hasClockCaveat, isDownloaded: side.isDownloaded,
                    isChosen: chosenID == side.id, digest: side.digest
                )
            },
            thisDeviceOrigin: "This Mac",
            resultMessage: resultMessage,
            onChoose: { chosenID = $0 },
            onExport: { _ in },
            onKeepBoth: { keptBoth = true },
            onClose: {}
        )
        .frame(minWidth: 960, minHeight: 640)
        .accessibilityIdentifier("playstead.harness.conflict-comparison")
    }

    private var resultMessage: String? {
        if keptBoth { return SaveVocabulary.resultAfterKeepingBoth.replacingOccurrences(of: "{Origin}", with: "This Mac") }
        guard let chosenID else { return nil }
        let origin = chosenID == "r1" ? "This Mac" : "Living Room Mac"
        let other = chosenID == "r1" ? "Living Room Mac" : "This Mac"
        return SaveVocabulary.resultAfterChoosing
            .replacingOccurrences(of: "{Origin}", with: origin)
            .replacingOccurrences(of: "{Other origin}", with: other)
    }
}
#endif
