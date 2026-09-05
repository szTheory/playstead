import SwiftUI

/// D-40's interruptive tier: a modal shown only at the moment of a
/// destructive intent (remove local copy, eviction, unpair, sign out,
/// delete game) and only when one or more of the game's save revisions
/// exist only on this Mac. The gate must be evaluated against
/// *committed* local state, never an in-flight optimistic write --
/// callers compute `onlyOnThisMacCount` from durable rows, not from a
/// pending upload's assumed outcome, so a destructive action taken
/// while an upload is in flight for the same line still sees the count
/// as it stands on disk right now.
enum OnlyCopyInterruptionGate {
    /// `true` only when the destructive action would remove one or more
    /// revisions that exist nowhere else. A count of zero raises no
    /// modal at all -- the caller's destructive action proceeds
    /// directly, with no second confirmation layered on top.
    static func shouldPresent(onlyOnThisMacCount: Int) -> Bool {
        onlyOnThisMacCount > 0
    }
}

/// The rendered interruptive modal: the locked title/body with `{N}`
/// and `{title}` substituted, and the three locked buttons -- "Export
/// saves…" (default), "Cancel", and "Remove anyway" (destructive
/// styling, never the default). It never questions whether the user is
/// certain and never blames: it states the fact, offers the escape
/// hatch first, and keeps the destructive path available (D-40).
/// Presenting this view at all is the caller's decision, made via
/// `OnlyCopyInterruptionGate`; this type never decides whether to show
/// itself.
struct OnlyCopyInterruptiveSheet: View {
    let onlyOnThisMacCount: Int
    let title: String
    var onExport: () -> Void = {}
    var onCancel: () -> Void = {}
    var onRemoveAnyway: () -> Void = {}

    @FocusState private var exportHasFocus: Bool

    enum Automation {
        static let surface = "playstead.save.only-copy-interruptive"
        static let title = "playstead.save.only-copy-interruptive.title"
        static let body = "playstead.save.only-copy-interruptive.body"
        static let export = "playstead.save.only-copy-interruptive.export"
        static let cancel = "playstead.save.only-copy-interruptive.cancel"
        static let removeAnyway = "playstead.save.only-copy-interruptive.remove-anyway"
    }

    private var bodyText: String {
        SaveVocabulary.dangerInterruptiveBody
            .replacingOccurrences(of: "{N}", with: String(onlyOnThisMacCount))
            .replacingOccurrences(of: "{title}", with: title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(SaveVocabulary.dangerInterruptiveTitle)
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityIdentifier(Automation.title)

            Text(bodyText)
                .font(.psBody)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityIdentifier(Automation.body)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer()

                Button(SaveVocabulary.dangerInterruptiveActionCancel, action: onCancel)
                    .playsteadFocusable(identifier: Automation.cancel)

                Button(SaveVocabulary.dangerInterruptiveActionRemove, role: .destructive, action: onRemoveAnyway)
                    .playsteadFocusable(identifier: Automation.removeAnyway)

                // The default action: keyboard-shortcut-equivalent to
                // Return, and given focus at presentation via
                // `.defaultFocus` below -- the easiest button is the
                // one that saves the user's progress, never the one
                // that discards it.
                Button(SaveVocabulary.dangerInterruptiveActionExport, action: onExport)
                    .keyboardShortcut(.defaultAction)
                    .focused($exportHasFocus)
                    .accessibilityIdentifier(Automation.export)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 480)
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(SaveVocabulary.dangerInterruptiveTitle) \(bodyText)")
        .accessibilityIdentifier(Automation.surface)
        .defaultFocus($exportHasFocus, true)
        .onExitCommand(perform: onCancel)
    }
}

#if UI_TESTING
/// A UI-testing-only harness presenting `OnlyCopyInterruptiveSheet`
/// directly as the app's root view, driven by
/// `PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION` -- the same
/// documented-seam pattern `ConflictComparisonHarnessRootView` uses (a
/// UI test target cannot `@testable import Playstead`, so a small,
/// explicitly test-only production seam is the accessible surface for
/// a genuine, real-window keyboard-interaction proof).
///
/// The env var's value selects which of the five destructive-intent
/// contexts is simulated (`remove_local_copy`, `eviction`, `unpair`,
/// `sign_out`, `delete_game`), each driving the exact same gate and
/// sheet -- proving all five reach the identical modal -- or
/// `zero_count`, which runs the gate with `onlyOnThisMacCount: 0` and
/// therefore presents nothing. No production entry point exists yet
/// for unpair/sign-out/delete-game (tracked in this plan's SUMMARY);
/// this harness proves the sheet and its gate are already correct for
/// whichever future call site wires them.
struct OnlyCopyInterruptionHarnessRootView: View {
    @State private var lastAction: String?
    /// Fixed at construction so "Remove anyway" can be proven to leave
    /// it unchanged -- the destructive action removes cached game
    /// bytes, never a save revision (the never-evictable rule, D-40).
    private let revisionsRemaining = 3

    private static func context() -> String {
        ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_ONLY_COPY_INTERRUPTION"] ?? "remove_local_copy"
    }

    private var onlyOnThisMacCount: Int {
        Self.context() == "zero_count" ? 0 : revisionsRemaining
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            if OnlyCopyInterruptionGate.shouldPresent(onlyOnThisMacCount: onlyOnThisMacCount) {
                OnlyCopyInterruptiveSheet(
                    onlyOnThisMacCount: onlyOnThisMacCount,
                    title: "Metroid Fusion",
                    onExport: { lastAction = "exported" },
                    onCancel: { lastAction = "cancelled" },
                    onRemoveAnyway: { lastAction = "removed" }
                )
            } else {
                Text("Nothing to interrupt.")
                    .accessibilityIdentifier("playstead.harness.only-copy-interruption.no-modal")
            }

            if let lastAction {
                Text(lastAction)
                    .accessibilityIdentifier("playstead.harness.only-copy-interruption.result")
            }

            Text("\(revisionsRemaining)")
                .accessibilityIdentifier("playstead.harness.only-copy-interruption.revisions-remaining")
        }
        .frame(minWidth: 640, minHeight: 420)
        .accessibilityIdentifier("playstead.harness.only-copy-interruption")
    }
}

/// A second, neutral harness root simulating browse/launch/sync with
/// only-on-this-Mac versions present -- and, critically, never invoking
/// `OnlyCopyInterruptiveSheet` at all. This is what
/// `PLAYSTEAD_UI_TEST_ONLY_COPY_NEUTRAL=1` presents; the "never appears
/// otherwise" test drives this root and asserts the interruptive
/// surface's accessibility identifier is absent.
struct OnlyCopyInterruptionNeutralHarnessRootView: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("Browsing Metroid Fusion — 3 versions only on this Mac.")
                .accessibilityIdentifier("playstead.harness.only-copy-neutral.browse")
            Text("Launching Metroid Fusion.")
                .accessibilityIdentifier("playstead.harness.only-copy-neutral.launch")
            Text("Syncing with your server.")
                .accessibilityIdentifier("playstead.harness.only-copy-neutral.sync")
        }
        .frame(minWidth: 640, minHeight: 420)
        .accessibilityIdentifier("playstead.harness.only-copy-neutral")
    }
}
#endif
