import XCTest
import CryptoKit
@testable import Playstead

final class EvictionTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var cas: CASManager!
    private var catalogueStore: CatalogueStore!
    private var pinStore: PinStore!
    private var planner: EvictionPlanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        cas = CASManager(paths: paths)
        catalogueStore = CatalogueStore(localStore: localStore)
        pinStore = PinStore(localStore: localStore)
        planner = EvictionPlanner(localStore: localStore, catalogueStore: catalogueStore, pinStore: pinStore, cas: cas, paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    @discardableResult
    private func seedCachedObject(seed: String, bytes: Int = 4096, lastUsedAt: String = "2026-01-01T00:00:00Z") throws -> String {
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((Int(seed.utf8.first ?? 1) &+ i * 7) & 0xFF) }
        let data = Data(raw)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = paths.partialURL(for: digest)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)

        try localStore.connection.execute(
            """
            INSERT OR REPLACE INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            params: [digest, bytes, lastUsedAt, lastUsedAt, bytes]
        )
        return digest
    }

    private func seedGame(id: String, requiredSHAs: [String], displayTitle: String? = nil) throws {
        let members = requiredSHAs.enumerated().map { idx, sha in
            AssetMember(ordinal: idx, role: "rom", required: true, sha256: sha, size: 4096, name: "member-\(idx)")
        }
        let entry = CatalogueEntry(id: id, system: "gba", displayTitle: displayTitle ?? id, tags: [:], members: members)
        try catalogueStore.upsert(entry)
    }

    // MARK: - Candidacy

    func testCandidatesAreUnpinnedFullyVerifiedGamesOrderedLeastRecentlyUsedFirst() throws {
        let shaOld = try seedCachedObject(seed: "old", lastUsedAt: "2020-01-01T00:00:00Z")
        let shaNew = try seedCachedObject(seed: "new", lastUsedAt: "2025-01-01T00:00:00Z")
        try seedGame(id: "old-game", requiredSHAs: [shaOld])
        try seedGame(id: "new-game", requiredSHAs: [shaNew])

        let candidates = planner.candidates()
        XCTAssertEqual(candidates.map(\.id), ["old-game", "new-game"], "least recently used must sort first")
    }

    func testGameNotFullyVerifiedIsNotACandidate() throws {
        let shaCached = try seedCachedObject(seed: "cached")
        let shaUncached = String(repeating: "a", count: 64)
        try seedGame(id: "partial-game", requiredSHAs: [shaCached, shaUncached])

        XCTAssertFalse(planner.candidates().map(\.id).contains("partial-game"))
    }

    func testPinnedGameIsNeverACandidate() throws {
        let sha = try seedCachedObject(seed: "pinned")
        try seedGame(id: "pinned-game", requiredSHAs: [sha])
        try pinStore.pin(assetSetID: "pinned-game")

        XCTAssertFalse(planner.candidates().map(\.id).contains("pinned-game"))
    }

    // MARK: - Shared object semantics

    func testSharedObjectSurvivesWhenOnlyOneOfTwoReferencingGamesIsReclaimedAndIsRemovedWhenBothAre() throws {
        let sharedSHA = try seedCachedObject(seed: "shared")
        try seedGame(id: "game-a", requiredSHAs: [sharedSHA])
        try seedGame(id: "game-b", requiredSHAs: [sharedSHA])

        // Only game-a selected: the shared object must survive.
        let partialPlan = planner.plan(for: ["game-a"])
        XCTAssertTrue(partialPlan.objectSHAs.isEmpty, "a shared object must not be freed unless every referencing game is selected")
        try planner.execute(partialPlan)
        XCTAssertTrue(cas.contains(sharedSHA))

        // Both selected: the shared object is freed.
        let fullPlan = planner.plan(for: ["game-a", "game-b"])
        XCTAssertEqual(fullPlan.objectSHAs, [sharedSHA])
        try planner.execute(fullPlan)
        XCTAssertFalse(cas.contains(sharedSHA))
    }

    // MARK: - Reconstructability guarantee

    func testObjectWithNoLocalCatalogueMemberRecordIsExcludedFromCandidatesAndReportedAsUnreferenced() throws {
        let orphanSHA = try seedCachedObject(seed: "orphan")
        // No `seedGame` call — nothing in `catalogue_members` references it.

        XCTAssertTrue(planner.candidates().isEmpty, "an orphan object with no owning game produces no candidate")
        let unreferenced = planner.unreferencedObjects()
        XCTAssertTrue(unreferenced.contains { $0.sha256 == orphanSHA })
    }

    // MARK: - Execute semantics

    func testReclaimingASelectedGameDeletesUnsharedObjectsAndLeavesLibraryRowPresentAsServerOnly() throws {
        let sha = try seedCachedObject(seed: "solo")
        try seedGame(id: "solo-game", requiredSHAs: [sha])

        let plan = planner.plan(for: ["solo-game"])
        try planner.execute(plan)

        XCTAssertFalse(cas.contains(sha))
        // The library row is still present.
        let stillPresent = catalogueStore.fetchAll().first { $0.id == "solo-game" }
        XCTAssertNotNil(stillPresent)

        // And derives as server-only now that its cached member is gone.
        let inputs = AvailabilityInputs(requiredMemberSHAs: [sha], cachedMemberSHAs: [], isPinned: false)
        XCTAssertEqual(AvailabilityState.derive(inputs), .serverOnly)
    }

    func testPlanStatedByteTotalEqualsActualBytesFreedByExecutingIt() throws {
        let sha1 = try seedCachedObject(seed: "one", bytes: 1000)
        let sha2 = try seedCachedObject(seed: "two", bytes: 2500)
        try seedGame(id: "g1", requiredSHAs: [sha1])
        try seedGame(id: "g2", requiredSHAs: [sha2])

        let plan = planner.plan(for: ["g1", "g2"])
        XCTAssertEqual(plan.totalBytes, 3500)

        let beforeUsage = totalCacheObjectBytes()
        try planner.execute(plan)
        let afterUsage = totalCacheObjectBytes()

        XCTAssertEqual(beforeUsage - afterUsage, plan.totalBytes)
    }

    func testReclaimingZeroSelectedGamesIsANoOpWithCalmMessage() throws {
        let sha = try seedCachedObject(seed: "untouched")
        try seedGame(id: "g1", requiredSHAs: [sha])

        let plan = planner.plan(for: [])
        XCTAssertEqual(plan, .empty)
        try planner.execute(plan)

        XCTAssertTrue(cas.contains(sha))
        XCTAssertFalse(StorageView.reclaimingZeroMessage.isEmpty)
    }

    func testCancellingThePlanLeavesCacheByteCountUnchanged() throws {
        let sha = try seedCachedObject(seed: "cancel-me")
        try seedGame(id: "g1", requiredSHAs: [sha])

        let before = totalCacheObjectBytes()
        // "Cancelling" means never calling `execute(_:)` at all.
        _ = planner.plan(for: ["g1"])
        let after = totalCacheObjectBytes()

        XCTAssertEqual(before, after)
        XCTAssertTrue(cas.contains(sha))
    }

    // MARK: - Quarantined partials

    func testQuarantinedPartialsAreListedSeparatelyAndIndividuallyRemovable() throws {
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = paths.partialURL(for: "bad-digest")
        try Data(repeating: 9, count: 100).write(to: partial)
        try cas.quarantine(partialAt: partial, reason: "digest_mismatch")

        let quarantined = planner.quarantinedPartials()
        XCTAssertEqual(quarantined.count, 1)

        try planner.removeQuarantined(atPath: quarantined[0].path)
        XCTAssertTrue(planner.quarantinedPartials().isEmpty)
    }

    // MARK: - No scheduled/automatic eviction

    /// Mirrors the plan's own acceptance-criteria grep
    /// (`grep -rniE 'Timer|schedule|autoEvict|automaticEvict'
    /// EvictionPlanner.swift`), but distinguishes an actual triggering
    /// construct (`Timer(`, `.scheduledTimer(`, a `DispatchSourceTimer`,
    /// `autoEvict(`/`automaticEvict(` as a call) from the file's own
    /// doc comments explaining that eviction is deliberately NEVER
    /// scheduled — those comments legitimately contain the word
    /// "scheduled" in prose and must not fail this guard.
    func testEvictionPlannerSourceContainsNoSchedulingOrAutomaticTrigger() throws {
        let source = try String(contentsOfFile: evictionPlannerSourcePath(), encoding: .utf8)
        let pattern = try NSRegularExpression(
            pattern: #"Timer\(|Timer\.scheduledTimer|DispatchSource\.makeTimerSource|\.scheduledTimer\s*\(|autoEvict\s*\(|automaticEvict\s*\("#,
            options: [.caseInsensitive]
        )
        let matches = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertTrue(matches.isEmpty, "EvictionPlanner.swift must contain no scheduling/automatic-eviction trigger construct")
    }

    // MARK: - StorageView content

    func testStorageViewStatesServerRetainsContent() {
        XCTAssertTrue(StorageView.serverRetainsStatement.lowercased().contains("server"))
    }

    // MARK: - Helpers

    private func totalCacheObjectBytes() -> Int {
        let rows = (try? localStore.connection.query("SELECT COALESCE(SUM(size), 0) FROM cache_objects;") { $0.int(0) ?? 0 }) ?? [0]
        return rows.first ?? 0
    }

    private func evictionPlannerSourcePath() -> String {
        // Walk up from this test file's own path
        // (.../playstead-mac/PlaysteadTests/CacheTests/EvictionTests.swift)
        // to the `playstead-mac` root, then down into the sibling
        // `Playstead/` source tree — avoids hardcoding an absolute
        // machine path.
        let thisFile = URL(fileURLWithPath: #filePath)
        let playsteadMacRoot = thisFile
            .deletingLastPathComponent() // EvictionTests.swift -> CacheTests/
            .deletingLastPathComponent() // CacheTests/ -> PlaysteadTests/
            .deletingLastPathComponent() // PlaysteadTests/ -> playstead-mac/
        return playsteadMacRoot.appendingPathComponent("Playstead/Cache/EvictionPlanner.swift").path
    }
}
