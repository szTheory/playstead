import XCTest
@testable import Playstead

/// Covers plan 04-06 task 3's `<behavior>` block: D-29 -- saves are
/// outside the quota, the 256 MiB save reserve, and never-evictable
/// saves surviving an evicted game.
final class SaveQuotaInteractionTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var catalogueStore: CatalogueStore!
    private var pinStore: PinStore!
    private var cas: CASManager!
    private var evictionPlanner: EvictionPlanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
        catalogueStore = CatalogueStore(localStore: localStore)
        pinStore = PinStore(localStore: localStore)
        cas = CASManager(paths: paths)
        evictionPlanner = EvictionPlanner(
            localStore: localStore, catalogueStore: catalogueStore, pinStore: pinStore, cas: cas, paths: paths,
            saveStore: SaveStore(localStore: localStore)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeManager(usage: Int, free: Int) -> QuotaManager {
        QuotaManager(localStore: localStore, cacheUsageProvider: { usage }, freeSpaceProvider: { free })
    }

    private func insertCacheObject(sha256: String, size: Int) throws {
        try localStore.connection.execute(
            """
            INSERT INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', ?, 1, 0);
            """,
            params: [sha256, size, size]
        )
    }

    private func insertGameWithCachedMember(assetSetID: String, sha256: String, size: Int, displayTitle: String = "Game") throws {
        try localStore.connection.execute(
            "INSERT INTO catalogue_entries (id, system, display_title, tags_json) VALUES (?, 'gba', ?, '[]');",
            params: [assetSetID, displayTitle]
        )
        try localStore.connection.execute(
            "INSERT INTO catalogue_members (asset_set_id, ordinal, role, required, sha256, size, name) VALUES (?, 0, 'rom', 1, ?, ?, 'rom');",
            params: [assetSetID, sha256, size]
        )
        try insertCacheObject(sha256: sha256, size: size)
    }

    @discardableResult
    private func insertSaveRevision(lineID: String, sizeBytes: Int) throws -> SaveRevisionRow {
        let row = SaveRevisionRow(
            id: UUID().uuidString, saveLineID: lineID, parentRevisionID: nil, blobSHA256: UUID().uuidString,
            sizeBytes: sizeBytes, originDeviceID: nil, deviceCapturedAt: nil, recordedAt: nil, captureMethod: nil,
            adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil, playSessionID: nil,
            durability: SaveDurability.localOnly.rawValue, localPath: nil,
            tier: SaveCaptureTier.promoted.rawValue, origin: SaveCaptureOrigin.session.rawValue,
            manifestDigest: nil, sessionID: nil, artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
        return row
    }

    // MARK: - 1. The quota sum over cache objects and save revisions equals the cache-objects-only sum.

    func test_quotaSum_overCacheObjectsAndSaveRevisions_equalsCacheObjectsOnlySum() throws {
        try insertCacheObject(sha256: "cache-object-1", size: 1_000_000)

        let manager = makeManager(usage: 0, free: .max) // cacheUsageProvider is stubbed below instead
        let cacheOnlyUsage = manager.usedBytes() // stub returns fixed value; assert the production provider instead

        // Exercise the real, un-stubbed provider (sums `cache_objects`
        // only) before and after a save revision exists -- adding a save
        // must never move this number.
        let realManager = QuotaManager(localStore: localStore, cacheRootURL: tempRoot)
        let beforeSave = realManager.usedBytes()

        let lineID = try saveStore.resolveLine(contentKey: "content-1", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        try insertSaveRevision(lineID: lineID, sizeBytes: 500_000_000) // far larger than the cache object

        let afterSave = realManager.usedBytes()

        XCTAssertEqual(beforeSave, 1_000_000)
        XCTAssertEqual(afterSave, beforeSave, "a save revision must never be counted toward cache usage")
        _ = cacheOnlyUsage
    }

    // MARK: - 2. The permitted download budget is reduced by exactly 268,435,456 bytes.

    func test_permittedDownloadBudget_isReducedByExactlyTheSaveReserve() {
        let floor = QuotaPolicy.defaultPolicy.floorBytes
        let manager = makeManager(usage: 0, free: floor + QuotaManager.saveReserveBytes + 1000)

        // With the reserve subtracted, exactly enough free space to leave
        // 999 bytes of headroom above the effective floor -- a transfer of
        // 999 bytes must be allowed, and 1001 must not.
        let allowed = manager.verdict(forAdditional: 999)
        let blocked = manager.verdict(forAdditional: 1001)

        XCTAssertTrue(allowed.allowed)
        XCTAssertFalse(blocked.allowed)
        XCTAssertEqual(blocked.limitHit, .floor)

        // The exact boundary: without the reserve, this same free space
        // would allow up to (free - floor) bytes; with the reserve, the
        // allowance is exactly 268_435_456 bytes smaller.
        let withoutReserveAllowance = (floor + QuotaManager.saveReserveBytes + 1000) - floor
        let withReserveAllowance = (floor + QuotaManager.saveReserveBytes + 1000) - (floor + QuotaManager.saveReserveBytes)
        XCTAssertEqual(withoutReserveAllowance - withReserveAllowance, QuotaManager.saveReserveBytes)
        XCTAssertEqual(QuotaManager.saveReserveBytes, 268_435_456)
    }

    // MARK: - 3. No save revision ever appears in the eviction candidate list.

    func test_evictionCandidates_neverIncludeASaveRevision_underMaximumQuotaPressure() throws {
        let assetSetID = "asset-1"
        try insertGameWithCachedMember(assetSetID: assetSetID, sha256: "rom-sha", size: 10_000_000)

        let lineID = try saveStore.resolveLine(contentKey: "content-2", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        let revision = try insertSaveRevision(lineID: lineID, sizeBytes: 999_999_999)

        // Maximum quota pressure: nothing pinned, everything fully cached.
        let candidates = evictionPlanner.candidates()
        XCTAssertFalse(candidates.isEmpty, "the game itself must still be a legitimate candidate")
        XCTAssertFalse(candidates.contains { $0.id == revision.id }, "no save revision id may ever appear as a candidate")
        XCTAssertFalse(candidates.contains { $0.bytes == revision.sizeBytes }, "a save revision's bytes must never be offered for reclaim")
    }

    // MARK: - 4. Evicting a game removes its cached bytes and leaves its save revision count unchanged.

    func test_evictingAGame_removesCachedBytes_leavesSaveRevisionCountUnchanged() throws {
        let assetSetID = "asset-2"
        try insertGameWithCachedMember(assetSetID: assetSetID, sha256: "rom-sha-2", size: 5_000_000)

        let lineID = try saveStore.resolveLine(contentKey: "content-3", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        try insertSaveRevision(lineID: lineID, sizeBytes: 32_768)
        try insertSaveRevision(lineID: lineID, sizeBytes: 32_768)

        let beforeCount = saveStore.fetchAllRevisions().filter { $0.saveLineID == lineID }.count
        XCTAssertEqual(beforeCount, 2)

        let plan = evictionPlanner.plan(for: [assetSetID])
        try evictionPlanner.execute(plan)

        let cacheRow = (try? localStore.connection.query("SELECT COUNT(*) FROM cache_objects WHERE sha256 = ?;", params: ["rom-sha-2"]) { $0.int(0) ?? 0 })?.first ?? -1
        XCTAssertEqual(cacheRow, 0, "the game's cached bytes must be gone")

        let afterCount = saveStore.fetchAllRevisions().filter { $0.saveLineID == lineID }.count
        XCTAssertEqual(afterCount, 2, "evicting the game must leave every save revision untouched")
    }

    // MARK: - 5. Unpinning a game does not make its saves evictable.

    func test_unpinningAGame_doesNotMakeItsSavesEvictable() throws {
        let assetSetID = "asset-3"
        try insertGameWithCachedMember(assetSetID: assetSetID, sha256: "rom-sha-3", size: 1_000_000)

        let lineID = try saveStore.resolveLine(contentKey: "content-4", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        let revision = try insertSaveRevision(lineID: lineID, sizeBytes: 65_536)

        try pinStore.pin(assetSetID: assetSetID)
        try pinStore.unpin(assetSetID: assetSetID)

        let candidates = evictionPlanner.candidates()
        XCTAssertFalse(candidates.contains { $0.id == revision.id })

        let afterCount = saveStore.fetchAllRevisions().filter { $0.saveLineID == lineID }.count
        XCTAssertEqual(afterCount, 1, "unpinning must never expose a save to eviction")
    }

    // MARK: - 6. No status rung, badge, or label is emitted for "never evictable".

    func test_noNeverEvictableStatusRung_isEmittedAnywhere() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Design/StatusToken.swift")
        let contents = try String(contentsOf: projectRoot, encoding: .utf8)
        XCTAssertFalse(contents.lowercased().contains("neverevictable"))
        XCTAssertFalse(contents.lowercased().contains("notevictable"))
    }
}
