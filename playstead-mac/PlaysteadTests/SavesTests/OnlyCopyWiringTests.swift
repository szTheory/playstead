import XCTest
import CryptoKit
@testable import Playstead

/// MC-01/MC-02: proves the D-40 interruptive gate and its export escape
/// hatch are reachable **from the assembled app**, not merely
/// constructible in isolation.
///
/// `OnlyCopyEscalationTests`, `OnlyCopyContractSnapshotTests`, and the
/// UI-test harness inside `OnlyCopyInterruptiveSheet.swift` all construct
/// the sheet/gate directly and assert it behaves correctly in isolation —
/// exactly the shape that let all four production call sites feed the
/// gate a hardcoded zero and survive 481 green tests. This suite does the
/// opposite: it builds the real composition root, drives only
/// `AppEnvironment.reclaimCandidateRows()` / `.storageSnapshot()` /
/// `.openConsoleSavesExport(forAssetSetIDs:)` — the exact calls
/// `GameRowView`, `LibraryShellView`, `ReclaimPromptView`, and
/// `StorageView` make — and never constructs `OnlyCopyInterruptiveSheet`
/// anywhere in this file.
@MainActor
final class OnlyCopyWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var environment: AppEnvironment!
    private var reachability: Reachability!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        environment = AppEnvironment(
            paths: paths,
            apiClient: apiClient,
            reachability: reachability,
            downloadSession: StubURLProtocol.makeSession()
        )
    }

    override func tearDownWithError() throws {
        environment = nil
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// A real 64-character lowercase-hex digest derived from `seed` —
    /// `CASManager.commit`/`PathSafety.validatedDigest` reject anything
    /// shorter, so a placeholder string like `"rom-1"` cannot stand in
    /// for a real sha256.
    private func digest(_ seed: String) -> String {
        SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func seedGame(id: String, title: String, digest: String) throws -> CatalogueEntry {
        let entry = CatalogueEntry(
            id: id,
            system: "gba",
            displayTitle: title,
            tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: digest, size: 4096, name: "rom.gba")]
        )
        try environment.catalogueStore.upsert(entry)
        environment.libraryViewModel.refresh()
        // A reclaim candidate must be fully cached to be offered at all
        // (`EvictionPlanner.candidates()`), so this fixture also commits
        // the required member into the real CAS.
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try Data(repeating: 0xAB, count: 4096).write(to: partial)
        try environment.casManager.commit(partialAt: partial, sha256: digest)
        try environment.localStore.connection.execute(
            """
            INSERT OR REPLACE INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            params: [digest, 4096, "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", 4096]
        )
        return entry
    }

    /// Commits one save revision for `digest`'s content key — exactly
    /// what `SaveCapturePoller` would have written, minus the actual
    /// emulator round trip.
    @discardableResult
    private func seedSaveRevision(
        contentKey: String, revisionID: String, durability: SaveDurability, blobSHA256: String = "save-blob"
    ) throws -> SaveLineRow {
        let line = try environment.saveStore.resolveLine(
            contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-\(contentKey)"
        )
        try environment.saveStore.insertRevision(
            SaveRevisionRow(
                id: revisionID,
                saveLineID: line.id,
                parentRevisionID: nil,
                blobSHA256: blobSHA256,
                sizeBytes: 128,
                originDeviceID: "device-1",
                deviceCapturedAt: nil,
                recordedAt: "2026-01-01T00:00:00Z",
                captureMethod: "poller",
                adapterID: nil,
                adapterVersion: nil,
                saveFormat: nil,
                formatConfidence: nil,
                playSessionID: nil,
                durability: durability.rawValue,
                localPath: nil
            )
        )
        return line
    }

    // MARK: - MC-01: the gate reads real counts from both reclaim surfaces

    /// `GameRowView`'s reclaim prompt calls `environment.reclaimCandidateRows()`
    /// with no override — this is the exact production path.
    func testReclaimCandidateRowsCarryRealOnlyOnThisMacCount() throws {
        let entry = try seedGame(id: "game-1", title: "Metroid Fusion", digest: digest("rom-digest-1"))
        try seedSaveRevision(contentKey: digest("rom-digest-1"), revisionID: "rev-1", durability: .localOnly)

        let rows = environment.reclaimCandidateRows()
        let row = try XCTUnwrap(rows.first(where: { $0.id == entry.id }))
        XCTAssertEqual(row.onlyOnThisMacCount, 1)
        XCTAssertTrue(
            OnlyCopyInterruptionGate.shouldPresent(onlyOnThisMacCount: row.onlyOnThisMacCount),
            "a game with a local-only revision must trip the gate on the path GameRowView actually drives"
        )
    }

    /// A game with no local-only revisions must report zero and must not
    /// trip the gate — proves this isn't merely "always nonzero."
    func testReclaimCandidateRowsReportZeroWhenEverythingIsUploaded() throws {
        let entry = try seedGame(id: "game-2", title: "Zelda", digest: digest("rom-digest-2"))
        try seedSaveRevision(contentKey: digest("rom-digest-2"), revisionID: "rev-2", durability: .uploaded)

        let rows = environment.reclaimCandidateRows()
        let row = try XCTUnwrap(rows.first(where: { $0.id == entry.id }))
        XCTAssertEqual(row.onlyOnThisMacCount, 0)
        XCTAssertFalse(OnlyCopyInterruptionGate.shouldPresent(onlyOnThisMacCount: row.onlyOnThisMacCount))
    }

    /// D-40: the count is read from committed state, never a pending
    /// upload's assumed outcome — a `queued` (in-flight) revision still
    /// counts as only-on-this-Mac.
    func testInFlightUploadStillCountsAsOnlyOnThisMac() throws {
        let entry = try seedGame(id: "game-3", title: "Contra", digest: digest("rom-digest-3"))
        try seedSaveRevision(contentKey: digest("rom-digest-3"), revisionID: "rev-3", durability: .queued)

        let count = environment.onlyOnThisMacCount(forAssetSetID: entry.id)
        XCTAssertEqual(count, 1, "an in-flight upload has not committed anything durable elsewhere yet")
        XCTAssertTrue(OnlyCopyInterruptionGate.shouldPresent(onlyOnThisMacCount: count))
    }

    /// `LibraryShellView` constructs `StorageView` from
    /// `environment.storageSnapshot().onlyOnThisMacCounts` — this is that
    /// exact map.
    func testStorageSnapshotCarriesRealOnlyOnThisMacCounts() throws {
        let entry = try seedGame(id: "game-4", title: "Pokemon", digest: digest("rom-digest-4"))
        try seedSaveRevision(contentKey: digest("rom-digest-4"), revisionID: "rev-4", durability: .localOnly)

        let snapshot = environment.storageSnapshot()
        XCTAssertEqual(snapshot.onlyOnThisMacCounts[entry.id], 1)
    }

    /// A candidate with no save activity at all must not appear in the
    /// map — `StorageView` treats a missing entry the same as zero.
    func testStorageSnapshotOmitsCandidatesWithNoOnlyCopyRevisions() throws {
        let entry = try seedGame(id: "game-5", title: "Kirby", digest: digest("rom-digest-5"))

        let snapshot = environment.storageSnapshot()
        XCTAssertNil(snapshot.onlyOnThisMacCounts[entry.id])
    }

    // MARK: - MC-02: the escape hatch actually resolves to a real destination

    /// The console's `/saves/:id` page (plan 04-10) for the game's
    /// committed save line — never a bare dismissal.
    func testConsoleSavesExportURLResolvesToTheCommittedSaveLine() throws {
        let entry = try seedGame(id: "game-6", title: "Metroid Fusion", digest: digest("rom-digest-6"))
        let line = try seedSaveRevision(contentKey: digest("rom-digest-6"), revisionID: "rev-6", durability: .localOnly)

        let url = environment.consoleSavesExportURL(forAssetSetID: entry.id, baseURL: credential.baseURL)
        XCTAssertEqual(url, credential.baseURL.appendingPathComponent("saves").appendingPathComponent(line.id))
    }

    /// No committed save line yet — the destination must be `nil`, never
    /// a URL pointing at nothing.
    func testConsoleSavesExportURLIsNilWithNoCommittedSaveLine() throws {
        let entry = try seedGame(id: "game-7", title: "No Saves Yet", digest: digest("rom-digest-7"))

        XCTAssertNil(environment.consoleSavesExportURL(forAssetSetID: entry.id, baseURL: credential.baseURL))
    }

    /// Choosing export must never perform the destructive reclaim —
    /// after opening the export destination, the candidate must still be
    /// fully present and reclaimable, exactly as it was before.
    func testOpeningConsoleExportNeverReclaimsAnything() async throws {
        let entry = try seedGame(id: "game-8", title: "Metroid Fusion", digest: digest("rom-digest-8"))
        try seedSaveRevision(contentKey: digest("rom-digest-8"), revisionID: "rev-8", durability: .localOnly)

        let before = environment.reclaimCandidateRows().map(\.id)
        XCTAssertTrue(before.contains(entry.id))

        await environment.openConsoleSavesExport(forAssetSetIDs: [entry.id])

        let after = environment.reclaimCandidateRows().map(\.id)
        XCTAssertEqual(before, after, "the escape hatch must never perform the destructive action")
        XCTAssertTrue(environment.casManager.contains(digest("rom-digest-8")), "export must not delete the cached object")
    }
}
