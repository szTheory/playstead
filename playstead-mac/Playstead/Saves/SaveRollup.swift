import Foundation

/// The inputs the game-level rollup (D-36) reads -- the newest
/// revision's own durability, scoped in the sentence, never a
/// minimum-of-durabilities reduction across every revision on the line.
struct SaveRollupInput: Equatable {
    /// `nil` when the game has no revisions at all -- the "No saves
    /// yet." case.
    let newestDurability: SaveDurability?
    /// Whether the line's current heads have diverged (D-38) -- first
    /// match wins over every durability header.
    let hasDivergentHeads: Bool
    /// Count of revisions, strictly older than the newest, whose
    /// durability is still `localOnly` -- feeds the muted second line
    /// and nothing else.
    let earlierLocalOnlyCount: Int
    let title: String
}

/// One rendered rollup: a header (always present), an optional body
/// line (only for the empty "No saves yet." case), an optional muted
/// second line, and an optional one-time footnote.
struct SaveRollupResult: Equatable {
    let header: String
    let bodyLine: String?
    let mutedSecondLine: String?
    let footnote: String?
}

/// D-36's game-level rollup. First-match-wins ordering: any divergent
/// head beats every durability header; the newest revision's own
/// durability (never a minimum-of-durabilities reduction across
/// revisions) drives the rest; no revisions at all yields the empty
/// state. Never claims a save was synced or archived in the sense this
/// phase's vocabulary rules forbid -- the destination is always "your
/// server".
enum SaveRollup {
    static func rollup(for input: SaveRollupInput, showFootnote: Bool = false) -> SaveRollupResult {
        let header: String
        var body: String?

        if input.hasDivergentHeads {
            header = SaveVocabulary.rollupHeaderTwoVersions
        } else if let durability = input.newestDurability {
            switch durability {
            case .localOnly:
                header = SaveVocabulary.rollupHeaderOnlyOnThisMac
            case .queued:
                header = SaveVocabulary.rollupHeaderWaitingToCopy
            case .uploaded:
                header = SaveVocabulary.rollupHeaderOnServer
            }
        } else {
            header = SaveVocabulary.rollupHeaderNoSaves
            body = SaveVocabulary.rollupNoSavesBody.replacingOccurrences(of: "{title}", with: input.title)
        }

        // Muted second line: only when count > 0, and never the only
        // line on its own -- it is always paired with the header above.
        var muted: String?
        if input.earlierLocalOnlyCount == 1 {
            muted = SaveVocabulary.rollupMutedLineSingular
        } else if input.earlierLocalOnlyCount > 1 {
            muted = SaveVocabulary.rollupMutedLinePlural
                .replacingOccurrences(of: "{N}", with: String(input.earlierLocalOnlyCount))
        }

        return SaveRollupResult(
            header: header,
            bodyLine: body,
            mutedSecondLine: muted,
            footnote: showFootnote ? SaveVocabulary.rollupFootnote : nil
        )
    }
}
