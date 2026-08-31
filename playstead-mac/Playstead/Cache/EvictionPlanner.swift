import Foundation

/// One unpinned, fully-verified game a user could choose to reclaim.
/// `bytes` is the byte count that reclaiming THIS game alone (with no
/// other game also selected) would free — i.e. only its unshared
/// objects. A shared object is only counted once a plan selects every
/// game that references it (see `EvictionPlanner.plan(for:)`), so this
/// per-candidate figure is deliberately conservative rather than an
/// optimistic sum.
struct EvictionCandidate: Equatable, Identifiable {
    let id: String
    let title: String
    let bytes: Int
    /// The most recent `last_used_at` among this game's cached required
    /// members — the LRU ordering key (`candidates()` sorts oldest
    /// first).
    let lastUsedAt: String
}

/// An explicit, named plan: exactly which cache objects a confirmed
/// reclaim will delete, and the total bytes that will free. `execute(_:)`
/// deletes exactly this set — nothing more, nothing inferred at delete
/// time (D-21: deletion is only ever reached through an explicit,
/// user-confirmed plan).
struct EvictionPlan: Equatable {
    let objectSHAs: Set<String>
    let totalBytes: Int

    static let empty = EvictionPlan(objectSHAs: [], totalBytes: 0)
}

/// An object present in `cache_objects` with no corresponding required
/// member record anywhere in the local catalogue mirror — it cannot be
/// fetched again from the server, so it is never offered as a reclaim
/// candidate. `StorageView` reports it separately so the user can decide
/// about it explicitly.
struct UnreferencedObject: Equatable, Identifiable {
    var id: String { sha256 }
    let sha256: String
    let bytes: Int
}

/// A partial download quarantined by a digest mismatch (D-23) —
/// individually removable, listed separately from reclaimable games.
struct QuarantinedPartial: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let bytes: Int
}

/// Computes and executes manual, LRU-ordered reclaim plans. Eviction is
/// manual only in this phase — never scheduled, timed, or triggered by a
/// threshold (D-21): the trust model has to be earned by the user
/// watching it behave before the app is allowed to do it unattended.
final class EvictionPlanner {
    private let localStore: LocalStore
    private let catalogueStore: CatalogueStore
    private let pinStore: PinStore
    private let cas: CASManager
    private let paths: AppPaths

    init(localStore: LocalStore, catalogueStore: CatalogueStore, pinStore: PinStore, cas: CASManager, paths: AppPaths) {
        self.localStore = localStore
        self.catalogueStore = catalogueStore
        self.pinStore = pinStore
        self.cas = cas
        self.paths = paths
    }

    /// Unpinned, fully verified games, ordered least-recently-used first.
    /// A game that is not fully verified locally is never a candidate.
    func candidates() -> [EvictionCandidate] {
        let pinned = pinStore.allPinned()
        let refs = referenceCounts()
        let sizes = cachedObjectSizes()
        let lastUsed = cachedObjectLastUsed()

        var result: [EvictionCandidate] = []
        for entry in catalogueStore.fetchAll() {
            guard !pinned.contains(entry.id) else { continue }
            let requiredSHAs = entry.members.filter { $0.required }.compactMap { $0.sha256 }
            guard !requiredSHAs.isEmpty else { continue }
            guard requiredSHAs.allSatisfy({ sizes[$0] != nil }) else { continue } // fully cached only

            let unsharedBytes = requiredSHAs.reduce(0) { sum, sha in
                let referencedBy = refs[sha] ?? []
                return referencedBy.count <= 1 ? sum + (sizes[sha] ?? 0) : sum
            }
            let gameLastUsed = requiredSHAs.compactMap { lastUsed[$0] }.max() ?? ""

            result.append(EvictionCandidate(id: entry.id, title: entry.displayTitle, bytes: unsharedBytes, lastUsedAt: gameLastUsed))
        }
        return result.sorted { $0.lastUsedAt < $1.lastUsedAt }
    }

    /// The explicit plan for reclaiming exactly `gameIDs`. An object is
    /// only included when EVERY game that declares it as a required
    /// member is also in `gameIDs` — a shared object survives unless
    /// every referencing game is selected together. `gameIDs.isEmpty`
    /// returns `.empty` (a no-op, calm-message plan).
    func plan(for gameIDs: Set<String>) -> EvictionPlan {
        guard !gameIDs.isEmpty else { return .empty }

        let refs = referenceCounts()
        let sizes = cachedObjectSizes()
        let entries = catalogueStore.fetchAll().filter { gameIDs.contains($0.id) }

        var objectSHAs: Set<String> = []
        var totalBytes = 0
        for entry in entries {
            for member in entry.members where member.required {
                guard let sha = member.sha256, let size = sizes[sha], !objectSHAs.contains(sha) else { continue }
                let referencedBy = refs[sha] ?? []
                if referencedBy.subtracting(gameIDs).isEmpty {
                    objectSHAs.insert(sha)
                    totalBytes += size
                }
            }
        }
        return EvictionPlan(objectSHAs: objectSHAs, totalBytes: totalBytes)
    }

    /// Deletes exactly the objects named by `plan` and updates
    /// `cache_objects`. Every affected game's library row remains — its
    /// `AvailabilityState` re-derives to `.serverOnly` on the next read
    /// because its cached members are simply gone, never because a row
    /// was deleted.
    func execute(_ plan: EvictionPlan) throws {
        for sha in plan.objectSHAs {
            try cas.remove(sha)
            try localStore.connection.execute("DELETE FROM cache_objects WHERE sha256 = ?;", params: [sha])
        }
    }

    /// Cached objects with no corresponding required-member record
    /// anywhere in the local catalogue mirror — cannot be redownloaded,
    /// so never a reclaim candidate.
    func unreferencedObjects() -> [UnreferencedObject] {
        let refs = referenceCounts()
        let sizes = cachedObjectSizes()
        return sizes.compactMap { sha, size in
            guard refs[sha] == nil else { return nil }
            return UnreferencedObject(sha256: sha, bytes: size)
        }.sorted { $0.sha256 < $1.sha256 }
    }

    /// Every quarantined partial under `partials/quarantine/`, listed
    /// separately from reclaimable games. Individually removable via
    /// `removeQuarantined(atPath:)`.
    func quarantinedPartials() -> [QuarantinedPartial] {
        let quarantineDir = paths.partials.appendingPathComponent("quarantine", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        return entries
            .filter { !$0.lastPathComponent.hasSuffix(".reason.txt") }
            .compactMap { url -> QuarantinedPartial? in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int) ?? 0
                return QuarantinedPartial(path: url.path, bytes: size)
            }
    }

    func removeQuarantined(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + ".reason.txt")
    }

    // MARK: - Shared helpers

    /// sha256 -> the set of asset_set_ids that declare it as a required
    /// catalogue member — used both to compute a candidate's unshared
    /// byte count and to decide whether `plan(for:)` may delete an
    /// object (only when every referencing id is in the selection).
    private func referenceCounts() -> [String: Set<String>] {
        let rows = (try? localStore.connection.query(
            "SELECT DISTINCT asset_set_id, sha256 FROM catalogue_members WHERE required = 1 AND sha256 IS NOT NULL;"
        ) { row -> (String, String) in (row.string(0) ?? "", row.string(1) ?? "") }) ?? []

        var map: [String: Set<String>] = [:]
        for (assetSetID, sha) in rows {
            map[sha, default: []].insert(assetSetID)
        }
        return map
    }

    private func cachedObjectSizes() -> [String: Int] {
        let rows = (try? localStore.connection.query(
            "SELECT sha256, size FROM cache_objects;"
        ) { row -> (String, Int) in (row.string(0) ?? "", row.int(1) ?? 0) }) ?? []
        return Dictionary(uniqueKeysWithValues: rows)
    }

    private func cachedObjectLastUsed() -> [String: String] {
        let rows = (try? localStore.connection.query(
            "SELECT sha256, last_used_at FROM cache_objects;"
        ) { row -> (String, String) in (row.string(0) ?? "", row.string(1) ?? "") }) ?? []
        return Dictionary(uniqueKeysWithValues: rows)
    }
}
