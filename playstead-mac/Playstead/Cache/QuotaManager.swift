import Foundation

/// The two-limit capacity policy: a byte quota (a preference about how
/// much of the disk the user wants to lend this app) and a free-space
/// floor on the cache volume (about whether the machine keeps working).
/// Defaults per D-21: 25 GiB quota, 10 GiB floor.
struct QuotaPolicy: Equatable {
    let quotaBytes: Int
    let floorBytes: Int

    static let gibibyte = 1024 * 1024 * 1024
    static let defaultPolicy = QuotaPolicy(quotaBytes: 25 * gibibyte, floorBytes: 10 * gibibyte)
}

enum QuotaLimitKind: Equatable {
    case quota
    case floor
}

/// The result of checking whether a prospective transfer of `bytes` may
/// start. A blocked verdict names which limit was hit and by how many
/// bytes — `ReclaimPromptView` renders that shortfall directly rather
/// than a vague "storage full" message.
struct QuotaVerdict: Equatable {
    let allowed: Bool
    let limitHit: QuotaLimitKind?
    let shortfallBytes: Int

    static let allow = QuotaVerdict(allowed: true, limitHit: nil, shortfallBytes: 0)
}

/// Measures the cache directory's total committed bytes and the
/// containing volume's free space, and answers whether an additional
/// transfer of a given size may start. The free-space floor outranks the
/// quota (D-21) — when both would be crossed, the verdict always names
/// the floor: a user who set a generous quota months ago did not consent
/// to filling their disk today.
///
/// `DownloadCoordinator` consults `verdict(forAdditional:)` before
/// starting each item (wired via its `quotaCheck` closure — see plan
/// 03-07 task 1). This type never deletes anything; a blocked verdict
/// only pauses the item and surfaces `ReclaimPromptView`.
final class QuotaManager {
    private let localStore: LocalStore
    private let cacheUsageProvider: () -> Int
    private let freeSpaceProvider: () -> Int

    /// `cacheUsageProvider`/`freeSpaceProvider` are injectable for tests;
    /// production defaults measure `cache_objects` and the real volume.
    init(
        localStore: LocalStore,
        cacheRootURL: URL? = nil,
        cacheUsageProvider: (() -> Int)? = nil,
        freeSpaceProvider: (() -> Int)? = nil
    ) {
        self.localStore = localStore
        self.cacheUsageProvider = cacheUsageProvider ?? {
            let rows = (try? localStore.connection.query(
                "SELECT COALESCE(SUM(size), 0) FROM cache_objects;"
            ) { row -> Int in row.int(0) ?? 0 }) ?? [0]
            return rows.first ?? 0
        }
        self.freeSpaceProvider = freeSpaceProvider ?? {
            guard let cacheRootURL else { return Int.max }
            let values = try? cacheRootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values?.volumeAvailableCapacityForImportantUsage {
                return Int(capacity)
            }
            return Int.max
        }
    }

    /// Reads the current policy, inserting the default row lazily on
    /// first read if none exists yet.
    func policy() -> QuotaPolicy {
        let rows = (try? localStore.connection.query(
            "SELECT quota_bytes, floor_bytes FROM quota_policy WHERE id = 1;"
        ) { row -> QuotaPolicy in
            QuotaPolicy(quotaBytes: row.int(0) ?? QuotaPolicy.defaultPolicy.quotaBytes, floorBytes: row.int(1) ?? QuotaPolicy.defaultPolicy.floorBytes)
        }) ?? []
        if let existing = rows.first {
            return existing
        }
        try? localStore.connection.execute(
            "INSERT OR IGNORE INTO quota_policy (id, quota_bytes, floor_bytes) VALUES (1, ?, ?);",
            params: [QuotaPolicy.defaultPolicy.quotaBytes, QuotaPolicy.defaultPolicy.floorBytes]
        )
        return QuotaPolicy.defaultPolicy
    }

    /// Sets the quota. Accepted even when it exceeds what the floor
    /// allows — the floor still governs every `verdict(forAdditional:)`
    /// call regardless of the configured quota (`QuotaSettingsView`
    /// states this plainly).
    func setQuota(bytes: Int) throws {
        _ = policy() // ensure a row exists
        try localStore.connection.execute(
            "UPDATE quota_policy SET quota_bytes = ? WHERE id = 1;",
            params: [bytes]
        )
    }

    /// The cache's current committed size, measured the same way
    /// `verdict(forAdditional:)` measures it — so `StorageView` and
    /// `QuotaSettingsView` report exactly the number the gate uses,
    /// never a second, separately-derived figure that could disagree.
    func usedBytes() -> Int {
        cacheUsageProvider()
    }

    /// Whether a transfer of `bytes` additional bytes may start right
    /// now. The floor is checked first and always wins when both limits
    /// would be crossed.
    func verdict(forAdditional bytes: Int) -> QuotaVerdict {
        let currentPolicy = policy()
        let currentUsage = cacheUsageProvider()
        let currentFree = freeSpaceProvider()

        let projectedFree = currentFree - bytes
        if projectedFree < currentPolicy.floorBytes {
            let shortfall = currentPolicy.floorBytes - projectedFree
            return QuotaVerdict(allowed: false, limitHit: .floor, shortfallBytes: max(0, shortfall))
        }

        let projectedUsage = currentUsage + bytes
        if projectedUsage > currentPolicy.quotaBytes {
            let shortfall = projectedUsage - currentPolicy.quotaBytes
            return QuotaVerdict(allowed: false, limitHit: .quota, shortfallBytes: max(0, shortfall))
        }

        return .allow
    }
}
