import SwiftUI

/// The card status ladder (03-UI-SPEC.md Status Vocabulary & Priority
/// Ladder, D-13/D-17). A card renders **exactly one** status slot,
/// selected by rank when more than one condition applies simultaneously.
/// `safeToEvict` is deliberately **not** a case here — it belongs to the
/// storage view (plan 03-07), never a card badge.
enum LibraryStatus: Equatable {
    case needsAttention
    case missingDependency
    case downloading(percent: Int)
    case queued
    case pinned
    case verified
    case serverOnly

    /// Lower value = higher priority (rank 1 outranks rank 6).
    /// `.pinned` and `.verified` share rank 5 per the UI-SPEC table —
    /// pinned always implies verified (D-21), so a row is never
    /// simultaneously both in practice.
    var rank: Int {
        switch self {
        case .needsAttention: return 1
        case .missingDependency: return 2
        case .downloading: return 3
        case .queued: return 4
        case .pinned, .verified: return 5
        case .serverOnly: return 6
        }
    }

    /// A stable, distinct identifier per state (SF Symbol name) — also
    /// used by tests to assert every state renders a distinct glyph.
    /// `.downloading` has no static glyph; it renders as a determinate
    /// ring instead (see `StatusSlotView.body`).
    var glyphIdentifier: String {
        switch self {
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .missingDependency: return "wrench.and.screwdriver.fill"
        case .downloading: return "progress.ring"
        case .queued: return "clock"
        case .pinned: return "mappin.circle.fill"
        case .verified: return "checkmark.circle.fill"
        case .serverOnly: return "icloud"
        }
    }

    /// The list-view text label, shown alongside the glyph in
    /// `GameListView` (never color/glyph alone).
    var listViewLabel: String {
        switch self {
        case .needsAttention: return "Needs attention"
        case .missingDependency: return "Missing dependency"
        case .downloading(let percent): return "Downloading — \(percent)%"
        case .queued: return "Queued"
        case .pinned: return "Pinned"
        case .verified: return "Ready offline"
        case .serverOnly: return "On server"
        }
    }

    /// A full-sentence accessible name — never satisfied by a tooltip or
    /// `title` attribute alone (03-UI-SPEC.md Accessibility Floor).
    func accessibleName(title: String) -> String {
        switch self {
        case .needsAttention: return "\(title) needs your attention."
        case .missingDependency: return "\(title) is missing something it needs to play."
        case .downloading(let percent): return "\(title) is downloading, \(percent) percent complete."
        case .queued: return "\(title) is queued to download."
        case .pinned: return "\(title) is pinned and ready to play offline."
        case .verified: return "\(title) is downloaded and ready to play offline."
        case .serverOnly: return "\(title) is on your server. Choose Download to play it offline."
        }
    }

    /// The single indicator a card renders when more than one status
    /// condition applies simultaneously — the highest-ranked (lowest
    /// `rank`) entry wins; `nil` when `statuses` is empty.
    static func highestPriority(among statuses: [LibraryStatus]) -> LibraryStatus? {
        statuses.min(by: { $0.rank < $1.rank })
    }
}

/// Renders exactly one status indicator — the highest-ranked entry in
/// `statuses`. Downloading renders as a determinate ring (03-UI-SPEC.md
/// Motion & Focus Specification); every other state is a glyph with its
/// own shape and color, never color alone (QUAL-01).
struct StatusSlotView: View {
    let statuses: [LibraryStatus]
    let title: String

    private var selected: LibraryStatus? {
        LibraryStatus.highestPriority(among: statuses)
    }

    var body: some View {
        Group {
            if let selected {
                if case .downloading(let percent) = selected {
                    ProgressView(value: Double(percent), total: 100)
                        .progressViewStyle(.circular)
                        .tint(StatusToken.color(for: selected))
                } else {
                    Image(systemName: selected.glyphIdentifier)
                        .foregroundStyle(StatusToken.color(for: selected))
                }
            }
        }
        .frame(minWidth: DesignTokens.InteractiveTarget.minimum, minHeight: DesignTokens.InteractiveTarget.minimum)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selected.map { $0.accessibleName(title: title) } ?? "")
    }
}
