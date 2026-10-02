import Foundation

/// The orderings the library list offers.
///
/// "Date added" is deliberately **not** one of them, and this is a decided
/// question rather than an open one (WINDOWS #79). Nothing in the client knows
/// when a game was added: `CatalogueEntry` carries id/system/displayTitle/
/// tags/members and no date at all, and the server's catalogue payload has a
/// FROZEN key set (`Playstead.Catalogue.Payload.frozen_keys`, with a test
/// asserting no accidental additions) exposing `updated_at` but no
/// `inserted_at`. Offering the control would mean inventing an order or
/// fabricating a date.
///
/// The case used to survive in this enum as a record of that reasoning, with
/// `sortedEntries` returning its input unchanged for it -- an unreachable
/// branch kept alive by a comment. The reasoning belongs in prose and in
/// 03-UI-SPEC, which now promises exactly two sort options; adding the third
/// is a protocol change (one frozen key, one client field) and should be
/// planned as one.
enum LibrarySortOption: String, CaseIterable {
    case title, system

    /// The options the picker offers. Asserted equal to `allCases`, so a new
    /// case cannot be added without either being offered or this list being
    /// changed deliberately -- the failure mode that let an unreachable
    /// ordering sit here in the first place.
    static let selectable: [LibrarySortOption] = [.title, .system]

    var controlLabel: String {
        switch self {
        case .title: return "Title"
        case .system: return "System"
        }
    }

    var controlIdentifier: String { "playstead.control.sort-\(rawValue)" }

    /// Case- and diacritic-insensitive ordering with a total tie-break, so
    /// "metroid" and "Metroid" sort together and equal keys never reshuffle.
    private static func ordered(_ lhs: String, _ rhs: String, tieBreak: (String, String)) -> Bool {
        switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return tieBreak.0 < tieBreak.1
        @unknown default: return tieBreak.0 < tieBreak.1
        }
    }

    /// Orders catalogue entries for the list layout.
    ///
    /// Ties break on `id` so the order is total: two games sharing a title,
    /// or every game in a single-system view, must not reshuffle between
    /// two evaluations of the same body.
    static func sortedEntries(_ entries: [CatalogueEntry], by sort: LibrarySortOption) -> [CatalogueEntry] {
        switch sort {
        case .title:
            return entries.sorted { ordered($0.displayTitle, $1.displayTitle, tieBreak: ($0.id, $1.id)) }
        case .system:
            return entries.sorted { ordered($0.system, $1.system, tieBreak: ($0.id, $1.id)) }
        }
    }
}
