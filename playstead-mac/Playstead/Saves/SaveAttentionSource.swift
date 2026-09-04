import Foundation

/// D-38/D-66: the Mac's own saves attention items -- unioned into the
/// card's existing rank-1 `needsAttention` rung and (once a Mac attention
/// inbox surface exists) into that inbox's list. There is no
/// `Playstead.Attention.Reason` on this client to widen -- `LibraryStatus`'s
/// rank-1 rung is the client's whole "attention" concept, and this type
/// is the divergence/blocked-capture half of what feeds it. This source
/// is pure: every function below takes already-resolved facts and
/// returns a value, with no database or network access of its own, so it
/// is testable with no `LocalStore` at all.
enum SaveAttentionReason: Equatable {
    case divergence(saveLineID: String, headCount: Int)
    case captureBlocked(saveLineID: String)
}

/// One divergence-attention candidate line -- everything
/// `SaveAttentionSource` needs to decide whether, and what, to raise for
/// one game. `originNames` is caller-resolved (mirrors
/// `SaveHistorySheet.deviceName`'s already-caller-supplied precedent);
/// this type never resolves a device id to a display name itself.
struct SaveAttentionCandidate: Equatable {
    let saveLineID: String
    let assetSetID: String
    let title: String
    /// Every current head of this line, in a stable order matching
    /// `originNames` -- computed by the caller from `SaveStore.fetchHeads`,
    /// never stored or re-derived here.
    let headRevisionIDs: [String]
    /// The origin device name for each entry in `headRevisionIDs`, same
    /// order, same count.
    let originNames: [String]
}

struct SaveAttentionItem: Identifiable, Equatable {
    let id: String
    let assetSetID: String
    let title: String
    let body: String
    let primaryAction: String
    let reason: SaveAttentionReason
}

enum SaveAttentionSource {
    /// True when `headRevisionIDs` is a genuine, undisposed fork -- more
    /// than one head, and no prior disposition recorded for this *exact*
    /// sorted head-id set (D-52's exact-match rule, mirrored from the
    /// server's `fork_acknowledged?/3`). A later, different fork on the
    /// same line (a new head-id set) re-raises even though an earlier
    /// fork here was disposed; switching sides after a disposition does
    /// not, by itself, change the head-id set, so it stays suppressed.
    static func hasUnacknowledgedDivergence(headRevisionIDs: [String], disposedHeadIDs: [String]?) -> Bool {
        guard headRevisionIDs.count > 1 else { return false }
        guard let disposedHeadIDs else { return true }
        return Set(headRevisionIDs) != Set(disposedHeadIDs)
    }

    /// One divergence attention item per candidate whose fork is still
    /// undecided. `disposedHeadIDs` is an injected lookup (never a direct
    /// `SaveStore` call) so this function stays pure. Every string here
    /// is the locked vocabulary, verbatim, with its N-variant used once
    /// the head count exceeds two (never a fresh N-2/N-3 ladder).
    static func divergenceItems(
        candidates: [SaveAttentionCandidate],
        disposedHeadIDs: (String) -> [String]?
    ) -> [SaveAttentionItem] {
        candidates.compactMap { candidate in
            guard hasUnacknowledgedDivergence(
                headRevisionIDs: candidate.headRevisionIDs,
                disposedHeadIDs: disposedHeadIDs(candidate.saveLineID)
            ) else { return nil }

            let count = candidate.headRevisionIDs.count
            let title: String
            let body: String
            if count > 2 {
                title = SaveVocabulary.attentionItemTitlePlural
                    .replacingOccurrences(of: "{N}", with: "\(count)")
                    .replacingOccurrences(of: "{title}", with: candidate.title)
                body = SaveVocabulary.attentionItemBodyPlural
                    .replacingOccurrences(of: "{N}", with: "\(count)")
                    .replacingOccurrences(of: "{title}", with: candidate.title)
            } else {
                title = SaveVocabulary.attentionItemTitle
                    .replacingOccurrences(of: "{title}", with: candidate.title)
                let originA = candidate.originNames.first ?? ""
                let originB = candidate.originNames.dropFirst().first ?? ""
                body = SaveVocabulary.attentionItemBody
                    .replacingOccurrences(of: "{title}", with: candidate.title)
                    .replacingOccurrences(of: "{Origin A}", with: originA)
                    .replacingOccurrences(of: "{Origin B}", with: originB)
            }

            return SaveAttentionItem(
                id: "divergence:\(candidate.saveLineID)",
                assetSetID: candidate.assetSetID,
                title: title,
                body: body,
                primaryAction: SaveVocabulary.attentionPrimaryAction,
                reason: .divergence(saveLineID: candidate.saveLineID, headCount: count)
            )
        }
    }

    /// One blocked-capture attention item per still-open blockage.
    /// Reuses the shipped `blocker.save_directory.*` strings (D-31's
    /// existing readiness-blocker copy) rather than inventing new
    /// vocabulary for what is the same underlying condition, so this
    /// source adds zero new locked strings.
    static func blockedCaptureItems(
        blockages: [(saveLineID: String, assetSetID: String, title: String, row: SaveCaptureBlockedRow)]
    ) -> [SaveAttentionItem] {
        blockages
            .filter { $0.row.resolvedAt == nil }
            .map { blockage in
                SaveAttentionItem(
                    id: "capture-blocked:\(blockage.saveLineID)",
                    assetSetID: blockage.assetSetID,
                    title: SaveVocabulary.blockerSaveDirectoryTitle,
                    body: SaveVocabulary.blockerSaveDirectoryFinding,
                    primaryAction: SaveVocabulary.blockerSaveDirectoryRemedy,
                    reason: .captureBlocked(saveLineID: blockage.saveLineID)
                )
            }
    }

    /// The full union this plan's `<behavior>` describes: divergence
    /// items, then blocked-capture items, in that order (divergence is
    /// this source's primary concern; capture-blocked is carried through
    /// from plan 04-06 unchanged).
    static func allItems(
        divergenceCandidates: [SaveAttentionCandidate],
        disposedHeadIDs: (String) -> [String]?,
        blockages: [(saveLineID: String, assetSetID: String, title: String, row: SaveCaptureBlockedRow)]
    ) -> [SaveAttentionItem] {
        divergenceItems(candidates: divergenceCandidates, disposedHeadIDs: disposedHeadIDs)
            + blockedCaptureItems(blockages: blockages)
    }

    /// The grouped header/secondary-action pair for the attention inbox
    /// when two or more games each have their own divergence item --
    /// `nil` when fewer than two, since the grouped copy only makes
    /// sense once there is something to group.
    static func groupedDivergenceSummary(items: [SaveAttentionItem]) -> (header: String, secondaryAction: String)? {
        let divergenceCount = items.reduce(into: 0) { count, item in
            if case .divergence = item.reason { count += 1 }
        }
        guard divergenceCount > 1 else { return nil }
        return (
            header: SaveVocabulary.attentionGroupedHeader.replacingOccurrences(of: "{N}", with: "\(divergenceCount)"),
            secondaryAction: SaveVocabulary.attentionGroupedSecondaryAction.replacingOccurrences(of: "{N}", with: "\(divergenceCount)")
        )
    }
}
