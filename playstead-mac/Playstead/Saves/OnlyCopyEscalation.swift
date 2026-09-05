import SwiftUI

/// D-32/D-40: the classification of why `SaveUploadLane`'s current
/// upload attempt for a line has not completed. Only four of these
/// values represent something the system genuinely cannot fix on its
/// own; the rest -- an offline queue and a slow in-flight upload -- are
/// the product working correctly and must never escalate. D-40's
/// central rule: escalate on undecidability, never on duration or
/// count.
enum SaveUploadFailureClassification: Equatable {
    /// Nothing is currently failing -- the line has no pending upload,
    /// or its pending upload is progressing normally. This is also how
    /// an old local-only version with a reachable server is expressed:
    /// there is no unfixable failure, however many days have passed.
    case none
    /// The lane is retrying because the server is unreachable. This
    /// resolves itself the moment connectivity returns, with zero user
    /// action -- it is success, not failure.
    case offlineQueue
    /// A large upload is in flight and simply has not finished yet, no
    /// matter how long it has been running.
    case slowUpload
    /// The device's credential was revoked server-side.
    case revokedAuth
    /// The server's declared capabilities no longer match what this
    /// Mac's client version requires.
    case capabilitySkew
    /// The server rejected the upload outright and the lane cannot
    /// resolve it by retrying.
    case serverRefusal
    /// The server rejected the revision as incompatible with the line
    /// it targets.
    case compatibilityRejection
}

/// D-32/D-40's four unfixable reasons, each carrying its own
/// user-facing phrase substituted into
/// `SaveVocabulary.dangerEscalatedBody`'s `{reason}` slot. Every phrase
/// avoids the save-surface banned-word list (never "sync", "revision",
/// etc.) and states the fact without blaming the user.
enum OnlyCopyEscalationReason: Equatable {
    case revokedAuth
    case capabilitySkew
    case serverRefusal
    case compatibilityRejection

    /// `nil` for every classification that must never escalate --
    /// `.none`, `.offlineQueue`, and `.slowUpload` all return `nil`
    /// here, which is what makes escalating them structurally
    /// impossible rather than merely untested.
    init?(classification: SaveUploadFailureClassification) {
        switch classification {
        case .revokedAuth: self = .revokedAuth
        case .capabilitySkew: self = .capabilitySkew
        case .serverRefusal: self = .serverRefusal
        case .compatibilityRejection: self = .compatibilityRejection
        case .none, .offlineQueue, .slowUpload: return nil
        }
    }

    var phrase: String {
        switch self {
        case .revokedAuth:
            return "this Mac's connection to your server is no longer valid"
        case .capabilitySkew:
            return "your server no longer accepts saves from this Mac's version of Playstead"
        case .serverRefusal:
            return "your server has refused this Mac's attempts to send it"
        case .compatibilityRejection:
            return "your server can't accept this version in its current form"
        }
    }
}

/// The classifier's full input: how many revisions on this game's save
/// line exist only on this Mac, the game's title (for substitution),
/// and the upload lane's current failure classification for that line.
/// Deliberately carries no date, timestamp, or running-time field --
/// D-40 forbids escalating on duration or count, so the type deciding
/// escalation cannot even represent one.
struct OnlyCopyEscalationInput: Equatable {
    let onlyOnThisMacCount: Int
    let title: String
    let failureClassification: SaveUploadFailureClassification
}

/// One rendered escalation: the locked title/body (with `{N}`,
/// `{title}`, and `{reason}` substituted) plus the reason code driving
/// it, so a caller can route "Fix this" appropriately.
struct OnlyCopyEscalationResult: Equatable {
    let reason: OnlyCopyEscalationReason
    let title: String
    let body: String
}

/// D-32/D-40's escalated-tier classifier: a pure function from
/// `OnlyCopyEscalationInput` to either no escalation or one rendered
/// escalation. Escalates only when the system cannot fix the situation
/// itself; an offline queue, a slow upload, and an old local-only
/// version -- however many days old, and however reachable the server
/// is -- are all the product working, and escalating them means
/// escalating success.
enum OnlyCopyEscalation {
    static func evaluate(_ input: OnlyCopyEscalationInput) -> OnlyCopyEscalationResult? {
        guard input.onlyOnThisMacCount > 0 else { return nil }
        guard let reason = OnlyCopyEscalationReason(classification: input.failureClassification) else { return nil }

        let body = SaveVocabulary.dangerEscalatedBody
            .replacingOccurrences(of: "{N}", with: String(input.onlyOnThisMacCount))
            .replacingOccurrences(of: "{title}", with: input.title)
            .replacingOccurrences(of: "{reason}", with: reason.phrase)

        return OnlyCopyEscalationResult(reason: reason, title: SaveVocabulary.dangerEscalatedTitle, body: body)
    }
}

/// D-40's escalated-tier panel: persistent and inline within a game's
/// save section, never a banner, a toast, or a notification, and
/// carrying no colour as a distinguisher. Renders only when its caller
/// passes a non-nil `OnlyCopyEscalationResult` -- callers construct
/// that result via `OnlyCopyEscalation.evaluate`, never inline.
struct OnlyCopyEscalationPanel: View {
    let escalation: OnlyCopyEscalationResult
    var onFix: () -> Void = {}
    var onExport: () -> Void = {}
    var onWhatsStoredWhere: () -> Void = {}

    enum Automation {
        static let surface = "playstead.save.only-copy-escalation"
        static let title = "playstead.save.only-copy-escalation.title"
        static let body = "playstead.save.only-copy-escalation.body"
        static let fix = "playstead.save.only-copy-escalation.fix"
        static let export = "playstead.save.only-copy-escalation.export"
        static let whatsStoredWhere = "playstead.save.only-copy-escalation.whats-stored-where"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(escalation.title)
                .font(.psLabelEmphasized)
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityIdentifier(Automation.title)

            Text(escalation.body)
                .font(.psLabel)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityIdentifier(Automation.body)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(SaveVocabulary.dangerEscalatedActionFix, action: onFix)
                    .playsteadFocusable(identifier: Automation.fix)
                Button(SaveVocabulary.dangerEscalatedActionExport, action: onExport)
                    .playsteadFocusable(identifier: Automation.export)
                Button(SaveVocabulary.dangerEscalatedActionWhatsStored, action: onWhatsStoredWhere)
                    .playsteadFocusable(identifier: Automation.whatsStoredWhere)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignTokens.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(escalation.title) \(escalation.body)")
        .accessibilityIdentifier(Automation.surface)
    }
}
