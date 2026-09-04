import SwiftUI

/// One revision's fully truthful, session-scoped reading for the
/// history sheet's rows -- built straight from `SaveStateModel`'s three
/// axes (D-35), never a collapsed status enum. Durability is read from
/// whatever the caller already loaded from SQLite; this view never
/// hashes anything at render.
struct SaveHistoryRevisionRow: Identifiable, Equatable {
    let id: String
    let durability: SaveDurability
    let isCurrent: Bool
    let isRestoredHere: Bool
    /// The lineage axis (D-35's sixth state, "Separate version") --
    /// true when this revision is one of two-or-more current heads on
    /// its line, per `SaveStateModel.isConflicted`. A row can be a
    /// separate version and any durability at once.
    let isSeparateVersion: Bool
    let relativeTime: String

    init(
        id: String, durability: SaveDurability, isCurrent: Bool, isRestoredHere: Bool,
        isSeparateVersion: Bool = false, relativeTime: String
    ) {
        self.id = id
        self.durability = durability
        self.isCurrent = isCurrent
        self.isRestoredHere = isRestoredHere
        self.isSeparateVersion = isSeparateVersion
        self.relativeTime = relativeTime
    }
}

/// One open-to-close play session's captures, grouped together so a
/// session with five staged captures and one promotion renders as one
/// group, never a flat log of every capture (D-39).
struct SaveHistorySession: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let revisions: [SaveHistoryRevisionRow]
}

/// D-37/D-39: the per-game save history sheet, reached from the
/// readiness Save row and the game detail view. Introduces no new
/// sidebar noun -- the shipped eight-step sidebar order is unchanged by
/// this file. Session-grouped, zero new colour literal, no green, and a
/// glyph set disjoint from the card's status ladder.
struct SaveHistorySheet: View {
    let title: String
    let sessions: [SaveHistorySession]
    var onClose: () -> Void = {}

    @FocusState private var doneHasFocus: Bool

    enum Automation {
        static let surface = "playstead.surface.save-history"
        static let done = "playstead.save-history.done"

        static func sessionHeader(_ sessionSlot: Int) -> String { "playstead.save-history.session.\(sessionSlot)" }
        static func row(_ sessionSlot: Int, _ rowSlot: Int) -> String {
            "playstead.save-history.session.\(sessionSlot).row.\(rowSlot)"
        }
    }

    /// The save glyph set -- deliberately disjoint from
    /// `LibraryStatus.glyphIdentifier`'s ladder (D-39). Asserted so by
    /// test, not merely by convention.
    enum Glyph {
        static let localOnly = "internaldrive"
        static let waitingToCopy = "arrow.up.circle"
        static let onServer = "network"
        static let current = "location.fill"
        static let restored = "arrow.uturn.backward"
        static let separateVersion = "arrow.triangle.branch"

        static let all: Set<String> = [localOnly, waitingToCopy, onServer, current, restored, separateVersion]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(SaveVocabulary.vocabularyRulesNounTimeline)
                .font(.psHeading)
                .foregroundStyle(DesignTokens.textPrimary)

            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { sessionSlot, session in
                            SaveHistorySessionView(session: session, sessionSlot: sessionSlot)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .focused($doneHasFocus)
                    .accessibilityIdentifier(Automation.done)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 480, minHeight: 360)
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(SaveVocabulary.vocabularyRulesNounTimeline) for \(title)")
        .accessibilityIdentifier(Automation.surface)
        .focusSection()
        .defaultFocus($doneHasFocus, true)
        .onExitCommand(perform: onClose)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(SaveVocabulary.rollupHeaderNoSaves)
                .font(.psLabelEmphasized)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(SaveVocabulary.rollupNoSavesBody.replacingOccurrences(of: "{title}", with: title))
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SaveHistorySessionView: View {
    let session: SaveHistorySession
    let sessionSlot: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(session.deviceName)
                .font(.psLabelEmphasized)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityIdentifier(SaveHistorySheet.Automation.sessionHeader(sessionSlot))

            ForEach(Array(session.revisions.enumerated()), id: \.element.id) { rowSlot, revision in
                SaveHistoryRowView(revision: revision, sessionSlot: sessionSlot, rowSlot: rowSlot)
            }
        }
    }
}

private struct SaveHistoryRowView: View {
    let revision: SaveHistoryRevisionRow
    let sessionSlot: Int
    let rowSlot: Int

    /// The row's own state label -- current/restored/separate-version
    /// win over plain durability, since they're the more specific fact
    /// about this exact revision. Not mutually exclusive in the data
    /// (D-35): a revision can be current AND a separate version AND
    /// uploaded at once, but the row shows its single most relevant
    /// label, in this fixed priority order.
    private var label: String {
        if revision.isCurrent { return SaveVocabulary.statePositionCurrentLabel }
        if revision.isSeparateVersion { return SaveVocabulary.stateLineageSeparateVersionLabel }
        if revision.isRestoredHere {
            return SaveVocabulary.stateProvenanceRestoredLabel.replacingOccurrences(of: "{date}", with: revision.relativeTime)
        }
        switch revision.durability {
        case .localOnly: return SaveVocabulary.stateDurabilityLocalOnlyLabel
        case .queued: return SaveVocabulary.stateDurabilityWaitingLabel
        case .uploaded: return SaveVocabulary.stateDurabilityOnServerLabel
        }
    }

    private var glyph: String {
        if revision.isCurrent { return SaveHistorySheet.Glyph.current }
        if revision.isSeparateVersion { return SaveHistorySheet.Glyph.separateVersion }
        if revision.isRestoredHere { return SaveHistorySheet.Glyph.restored }
        switch revision.durability {
        case .localOnly: return SaveHistorySheet.Glyph.localOnly
        case .queued: return SaveHistorySheet.Glyph.waitingToCopy
        case .uploaded: return SaveHistorySheet.Glyph.onServer
        }
    }

    /// Reuses shipped, non-green status colors -- never a fresh
    /// `Color(hex:)` literal (D-39).
    private var color: Color {
        switch revision.durability {
        case .localOnly: return DesignTokens.textMuted
        case .queued: return StatusToken.queued
        case .uploaded: return StatusToken.serverOnly
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // The 28pt leading rail reserved for a future
            // save-progress screenshot (SEED-006, D-39) -- empty today.
            Color.clear
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Image(systemName: glyph)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.psLabelEmphasized)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(revision.relativeTime)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
            }

            Spacer()
        }
        .frame(minHeight: DesignTokens.InteractiveTarget.minimum)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SaveHistorySheet.Automation.row(sessionSlot, rowSlot))
    }
}
