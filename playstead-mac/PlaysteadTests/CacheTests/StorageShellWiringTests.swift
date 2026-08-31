import XCTest
import CryptoKit
@testable import Playstead

/// Proves the download-management slice — quota enforcement, the download
/// queue surface, and the storage/reclaim surfaces — is reachable **from
/// the assembled app**, not merely constructible in isolation.
///
/// `QuotaTests`, `EvictionTests` and `QueueTests` all build their own
/// `QuotaManager`, `EvictionPlanner`, `PinStore` and `DownloadQueue` by
/// hand, which is exactly why they all passed while none of those types
/// had a production call site and the shipped app enforced no quota at
/// all. This suite deliberately does the opposite: it constructs the real
/// composition root against a temporary directory and a stubbed
/// `URLProtocol`, then drives only the code paths the shipped UI drives.
@MainActor
final class StorageShellWiringTests: XCTestCase {
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
        // Nothing reaches the network unless a test scripts a responder.
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

    /// Deterministic bytes plus their real digest, so a download that
    /// actually transfers passes `DownloadEngine`'s digest verification.
    private func makePayload(seed: UInt8, bytes: Int = 4096) -> (data: Data, digest: String) {
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((Int(seed) &+ i * 7) & 0xFF) }
        let data = Data(raw)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (data, digest)
    }

    @discardableResult
    private func seedGame(id: String, title: String, digest: String, size: Int = 4096) throws -> CatalogueEntry {
        let entry = CatalogueEntry(
            id: id,
            system: "gba",
            displayTitle: title,
            tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: digest, size: size, name: "rom.gba")]
        )
        try environment.catalogueStore.upsert(entry)
        environment.libraryViewModel.refresh()
        return entry
    }

    /// Commits `data` into the app's own CAS and records its
    /// `cache_objects` row — the state a completed download leaves behind.
    private func commitIntoCache(_ data: Data, digest: String, lastUsedAt: String = "2026-01-01T00:00:00Z") throws {
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try environment.casManager.commit(partialAt: partial, sha256: digest)
        try environment.localStore.connection.execute(
            """
            INSERT OR REPLACE INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            params: [digest, data.count, lastUsedAt, lastUsedAt, data.count]
        )
    }

    private func serveBlob(_ data: Data) {
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: ["Content-Length": "\(data.count)"], body: data)
        }
    }

    // MARK: - The quota gate is genuinely on the real download path

    /// The heart of this suite. An over-quota download must be *refused*,
    /// not merely reported: no connection may be opened at all.
    func testOverQuotaDownloadIsRefusedWithoutOpeningAConnection() async throws {
        let payload = makePayload(seed: 1)
        let entry = try seedGame(id: "asset-1", title: "Metroid", digest: payload.digest)
        serveBlob(payload.data)

        // A quota that this 4 KiB download cannot fit under.
        environment.setQuota(bytes: 1024)

        // Exactly what `GameRowView`'s Download button invokes.
        let attempt = await environment.attemptDownload(for: entry)

        guard case .blocked(let verdict) = attempt else {
            return XCTFail("an over-quota download must be blocked, got \(attempt)")
        }
        XCTAssertEqual(verdict.limitHit, .quota)
        XCTAssertEqual(verdict.shortfallBytes, 4096 - 1024)
        XCTAssertTrue(
            StubURLProtocol.requestLog.isEmpty,
            "the gate must refuse before a connection is opened, not after the bytes have already landed"
        )
        XCTAssertFalse(environment.casManager.contains(payload.digest))
    }

    /// The same download, under a quota that fits, must actually transfer
    /// — otherwise the test above would pass against a gate that blocks
    /// everything.
    func testWithinQuotaDownloadActuallyTransfersAndCommits() async throws {
        let payload = makePayload(seed: 2)
        let entry = try seedGame(id: "asset-1", title: "Metroid", digest: payload.digest)
        serveBlob(payload.data)

        environment.setQuota(bytes: 64 * 1024)
        let attempt = await environment.attemptDownload(for: entry)

        XCTAssertEqual(attempt, .completed)
        XCTAssertFalse(StubURLProtocol.requestLog.isEmpty, "an allowed download must actually open a connection")
        XCTAssertTrue(environment.casManager.contains(payload.digest), "the object must be committed into the app's own CAS")
    }

    /// The verdict is measured against the *shared* `QuotaManager` the
    /// storage surfaces report from — cache already committed by an
    /// earlier download counts against the next one.
    func testAlreadyCachedBytesCountTowardTheNextDownloadsVerdict() async throws {
        let cached = makePayload(seed: 3)
        try commitIntoCache(cached.data, digest: cached.digest)

        let next = makePayload(seed: 4)
        let entry = try seedGame(id: "asset-2", title: "Contra", digest: next.digest)
        serveBlob(next.data)

        // Room for one 4 KiB object, but one is already committed.
        environment.setQuota(bytes: 6 * 1024)
        XCTAssertEqual(environment.quotaManager.usedBytes(), 4096)

        guard case .blocked(let verdict) = await environment.attemptDownload(for: entry) else {
            return XCTFail("the already-committed 4 KiB must count against the quota")
        }
        XCTAssertEqual(verdict.limitHit, .quota)
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty)
    }

    /// A member already in the CAS costs nothing, so a re-download of an
    /// entirely cached game is never blocked even at a zero quota.
    func testFullyCachedGameIsNotBlockedBecauseItAddsNoBytes() async throws {
        let payload = makePayload(seed: 5)
        try commitIntoCache(payload.data, digest: payload.digest)
        let entry = try seedGame(id: "asset-3", title: "Zelda", digest: payload.digest)

        // A quota with no headroom whatsoever: exactly the bytes already
        // committed. A download that adds nothing must still be allowed
        // through it.
        environment.setQuota(bytes: 4096)
        XCTAssertEqual(environment.pendingDownloadBytes(for: entry), 0)
        let attempt = await environment.attemptDownload(for: entry)
        XCTAssertEqual(attempt, .completed)
    }

    // MARK: - The reclaim prompt's buttons do real work

    /// `ReclaimPromptView`'s "Raise quota" button, end to end: the raise
    /// persists through the shared `QuotaManager`, and the retry that the
    /// prompt fires then actually succeeds.
    func testRaisingQuotaFromTheReclaimPromptUnblocksTheSameDownload() async throws {
        let payload = makePayload(seed: 6)
        let entry = try seedGame(id: "asset-1", title: "Metroid", digest: payload.digest)
        serveBlob(payload.data)
        environment.setQuota(bytes: 1024)

        guard case .blocked(let verdict) = await environment.attemptDownload(for: entry) else {
            return XCTFail("expected a blocked verdict to raise the quota against")
        }
        XCTAssertTrue(environment.canRaiseQuota(for: verdict))

        XCTAssertTrue(environment.raiseQuota(toCover: verdict))
        XCTAssertEqual(environment.quotaManager.policy().quotaBytes, 4096, "the raise must persist through the shared QuotaManager")

        // What `dismissReclaimPromptAndRetry` re-runs.
        let retry = await environment.attemptDownload(for: entry)
        XCTAssertEqual(retry, .completed)
    }

    /// The floor outranks the quota (D-21), so a floor-blocked download
    /// must never offer a "raise the quota" button that would change
    /// nothing.
    func testFloorBlockedVerdictOffersNoQuotaRaise() {
        let floorBlocked = QuotaVerdict(allowed: false, limitHit: .floor, shortfallBytes: 4096)
        XCTAssertFalse(environment.canRaiseQuota(for: floorBlocked))

        let before = environment.quotaManager.policy().quotaBytes
        XCTAssertFalse(environment.raiseQuota(toCover: floorBlocked))
        XCTAssertEqual(environment.quotaManager.policy().quotaBytes, before, "a floor block must not silently widen the quota")
    }

    /// `ReclaimPromptView`'s "Reclaim selected" button reclaims through a
    /// real `EvictionPlan` against the app's own planner, and the freed
    /// bytes are what the gate then measures.
    func testReclaimingFromThePromptFreesRealBytesAndUnblocksTheDownload() async throws {
        let stale = makePayload(seed: 7)
        try commitIntoCache(stale.data, digest: stale.digest, lastUsedAt: "2020-01-01T00:00:00Z")
        try seedGame(id: "old-game", title: "Old Game", digest: stale.digest)

        let wanted = makePayload(seed: 8)
        let entry = try seedGame(id: "asset-9", title: "New Game", digest: wanted.digest)
        serveBlob(wanted.data)
        environment.setQuota(bytes: 6 * 1024)

        guard case .blocked = await environment.attemptDownload(for: entry) else {
            return XCTFail("expected the cached 4 KiB to block the next 4 KiB")
        }

        // The candidate list the prompt renders, from the real planner.
        let rows = environment.reclaimCandidateRows()
        XCTAssertEqual(rows.map(\.id), ["old-game"])
        XCTAssertEqual(rows.first?.title, "Old Game")
        XCTAssertEqual(rows.first?.bytes, 4096)

        XCTAssertEqual(environment.reclaim(gameIDs: ["old-game"]), 4096)
        XCTAssertFalse(environment.casManager.contains(stale.digest), "reclaim must actually delete the object, not just report bytes")
        XCTAssertEqual(environment.quotaManager.usedBytes(), 0)

        let afterReclaim = await environment.attemptDownload(for: entry)
        XCTAssertEqual(afterReclaim, .completed)
    }

    /// Pinning must protect a game from reclaim through the same shared
    /// `PinStore` the row's Pin button writes to.
    func testPinningThroughTheRowProtectsAGameFromReclaim() throws {
        let payload = makePayload(seed: 9)
        try commitIntoCache(payload.data, digest: payload.digest)
        try seedGame(id: "old-game", title: "Old Game", digest: payload.digest)

        XCTAssertEqual(environment.reclaimCandidateRows().map(\.id), ["old-game"])

        // Exactly what `GameRowView`'s Pin button invokes.
        XCTAssertTrue(environment.togglePin(assetSetID: "old-game"))
        XCTAssertTrue(environment.isPinned(assetSetID: "old-game"))
        XCTAssertTrue(environment.reclaimCandidateRows().isEmpty, "a pinned game must not be offered for reclaim")
        XCTAssertTrue(
            environment.storageSnapshot().candidates.isEmpty,
            "the storage surface must not offer it either — the candidate list is the only route to a reclaim"
        )
        XCTAssertEqual(environment.storageSnapshot().pinnedGames.map(\.id), ["old-game"])
        XCTAssertTrue(environment.casManager.contains(payload.digest), "pinning alone must never delete anything")

        // Unpinning is not a deletion either — it only makes the game
        // eligible for a later, explicitly confirmed reclaim.
        XCTAssertFalse(environment.togglePin(assetSetID: "old-game"))
        XCTAssertTrue(environment.casManager.contains(payload.digest))
        XCTAssertEqual(environment.reclaimCandidateRows().map(\.id), ["old-game"])
    }

    // MARK: - Every toolbar surface is reachable and renders real data

    func testEveryShellSurfaceRoutesToATitledSurface() {
        for surface in LibraryShellView.ShellSurface.allCases {
            XCTAssertFalse(
                LibraryShellView.title(for: surface).isEmpty,
                "\(surface) must route somewhere, not to a blank sheet"
            )
        }
        XCTAssertEqual(
            Set(LibraryShellView.ShellSurface.allCases.map { LibraryShellView.title(for: $0) }),
            ["Adapter", "Downloads", "Storage"]
        )
    }

    /// `StorageView`/`QuotaSettingsView` are handed a snapshot of the real
    /// stores — the same used-bytes figure the gate measures against, the
    /// real pinned set, and the real candidate list.
    func testStorageSurfaceRendersRealDataNotPlaceholders() throws {
        let pinned = makePayload(seed: 10)
        try commitIntoCache(pinned.data, digest: pinned.digest)
        try seedGame(id: "pinned-game", title: "Pinned Game", digest: pinned.digest)
        environment.togglePin(assetSetID: "pinned-game")

        let evictable = makePayload(seed: 11)
        try commitIntoCache(evictable.data, digest: evictable.digest)
        try seedGame(id: "evictable-game", title: "Evictable Game", digest: evictable.digest)

        environment.setQuota(bytes: 32 * 1024)
        let snapshot = environment.storageSnapshot()

        XCTAssertEqual(snapshot.usedBytes, 8192)
        XCTAssertEqual(
            snapshot.usedBytes, environment.quotaManager.usedBytes(),
            "the surface must report exactly the figure the quota gate uses"
        )
        XCTAssertEqual(snapshot.policy.quotaBytes, 32 * 1024)
        XCTAssertEqual(snapshot.policy.floorBytes, QuotaPolicy.defaultPolicy.floorBytes)
        XCTAssertEqual(snapshot.pinnedGames.map(\.title), ["Pinned Game"], "pins must be resolved to real catalogue titles")
        XCTAssertEqual(snapshot.candidates.map(\.id), ["evictable-game"], "a pinned game is never a candidate")

        // The Reclaim button on that surface does real work.
        environment.reclaim(gameIDs: ["evictable-game"])
        XCTAssertEqual(environment.storageSnapshot().usedBytes, 4096)
    }

    /// The quota stepper on `QuotaSettingsView` writes through to the
    /// shared `QuotaManager`, so a change made there governs the next
    /// download attempt.
    func testQuotaSettingsStepperGovernsTheNextDownload() async throws {
        let payload = makePayload(seed: 12)
        let entry = try seedGame(id: "asset-1", title: "Metroid", digest: payload.digest)
        serveBlob(payload.data)

        // What the stepper's `onSetQuota` invokes.
        environment.setQuota(bytes: 1024)
        XCTAssertEqual(environment.storageSnapshot().policy.quotaBytes, 1024)
        guard case .blocked = await environment.attemptDownload(for: entry) else {
            return XCTFail("the quota set on the settings surface must govern the download path")
        }

        environment.setQuota(bytes: 64 * 1024)
        let raised = await environment.attemptDownload(for: entry)
        XCTAssertEqual(raised, .completed)
    }

    /// `DownloadsView`'s rows come from the app's own persistent
    /// `DownloadQueue`, resolved against the real catalogue, and its
    /// buttons mutate that same queue.
    func testDownloadsSurfaceRendersTheRealQueueAndItsButtonsMutateIt() throws {
        let first = makePayload(seed: 13)
        let second = makePayload(seed: 14)
        let entryOne = try seedGame(id: "asset-1", title: "Metroid", digest: first.digest)
        let entryTwo = try seedGame(id: "asset-2", title: "Contra", digest: second.digest)

        XCTAssertTrue(environment.downloadRows().isEmpty)

        // Offline, so the queue's own scheduler cannot race these
        // assertions by starting a transfer: this test is about the
        // persistent queue the surface renders, not the transfer.
        reachability.simulate(online: false)

        environment.enqueueDownload(for: entryOne)
        environment.enqueueDownload(for: entryTwo)

        var rows = environment.downloadRows()
        XCTAssertEqual(rows.map(\.title), ["Metroid", "Contra"], "rows must resolve real catalogue titles, not raw ids")
        XCTAssertEqual(rows.map(\.sizeBytes), [4096, 4096])
        XCTAssertEqual(rows.map(\.sha256), [first.digest, second.digest])
        XCTAssertNotEqual(DownloadsView.summary(for: rows), "Your queue is empty.")

        // Pause — what the row's Pause button invokes.
        let firstID = try XCTUnwrap(rows.first?.id)
        environment.pauseDownload(id: firstID)
        rows = environment.downloadRows()
        XCTAssertEqual(rows.first(where: { $0.id == firstID })?.state, .paused)

        // Reorder — what the row's chevrons invoke.
        let secondID = try XCTUnwrap(environment.downloadRows().last?.id)
        environment.moveDownloadUp(id: secondID)
        XCTAssertEqual(environment.downloadRows().first?.id, secondID, "reordering must persist in the shared queue")

        // Cancel.
        environment.cancelDownload(id: secondID)
        XCTAssertFalse(
            environment.downloadRows().contains { $0.id == secondID && $0.state != .cancelled },
            "cancelling must reach the shared queue"
        )
    }
}
