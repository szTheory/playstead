import Foundation

/// The frozen, six-value console availability filter vocabulary
/// (plan 03-13/03-14, LIBR-02 gap closure), mirroring
/// `Playstead.AvailabilityVocabulary` (Elixir) and
/// `shared/availability-vocabulary.json` exactly — the
/// `Saves/SaveVocabulary.swift`/`shared/save-vocabulary.json` contract
/// pattern (D-67), reused here.
///
/// This type exists ONLY so the two codebases are provably proven never
/// to drift apart on the six console filter values' labels and
/// accessible names, via `AvailabilityVocabularyContractTests`. It is
/// NOT the Mac client's own availability state: `AvailabilityState`
/// (six *different* cases, including the storage-view-only
/// `.safeToEvict`) remains the sole read-time derivation this client's
/// own UI ever renders from. No shipped Mac UI reads these constants
/// today — the console filter chips are server-rendered LiveView, not
/// Mac UI — and `shared/availability-vocabulary.json` is a test
/// resource only, never read from a shipped runtime code path.
enum AvailabilityVocabulary {
    static let needsAttention = "needs_attention"
    static let missingDependency = "missing_dependency"
    static let downloading = "downloading"
    static let readyOffline = "ready_offline"
    static let queued = "queued"
    static let serverOnly = "server_only"

    /// The six frozen filter values, in display order — mirrors
    /// `Playstead.AvailabilityVocabulary.values/0` exactly.
    static let values: [String] = [
        needsAttention, missingDependency, downloading, readyOffline, queued, serverOnly
    ]

    static let labels: [String: String] = [
        needsAttention: "Needs attention",
        missingDependency: "Missing dependency",
        downloading: "Downloading",
        readyOffline: "Ready offline",
        queued: "Queued",
        serverOnly: "On server",
    ]

    static let accessibleNames: [String: String] = [
        needsAttention: "Filter by needs attention",
        missingDependency: "Filter by missing dependency",
        downloading: "Filter by downloading",
        readyOffline: "Filter by ready offline",
        queued: "Filter by queued",
        serverOnly: "Filter by on server",
    ]

    /// `label(_:)`, or `nil` if `value` is not in the frozen vocabulary.
    static func label(_ value: String) -> String? { labels[value] }

    /// `accessible_name(_:)`, or `nil` if `value` is not in the frozen
    /// vocabulary.
    static func accessibleName(_ value: String) -> String? { accessibleNames[value] }

    /// `key -> value`, identical in content to
    /// `shared/availability-vocabulary.json`'s flat
    /// `filter.{value}.{label|accessible_name}` keys — the
    /// `SaveVocabulary.all` pattern. The contract test parses the JSON
    /// and asserts this dictionary is exactly equal to it, exhaustively
    /// in both directions.
    static let all: [String: String] = {
        var dict: [String: String] = [:]
        for value in values {
            dict["filter.\(value).label"] = labels[value]
            dict["filter.\(value).accessible_name"] = accessibleNames[value]
        }
        return dict
    }()
}
