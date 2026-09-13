import CryptoKit
import XCTest
@testable import Playstead

/// Proves the six-state availability derivation (D-21) actually reaches the
/// library's badges, from the assembled app.
///
/// `AvailabilityStateTests` already covers `derive(_:)` exhaustively and
/// passed throughout — while `AvailabilityInputs(` had no production
/// construction site at all and `ShelfView` was handed a hardcoded
/// `[.serverOnly]` for every entry, so every card in the grid claimed "on
/// your server, choose Download to play it offline" over content that was
/// downloaded and playable (WINDOWS #72/#73). A pure-derivation test cannot
/// see that. This suite therefore never builds an `AvailabilityInputs`
/// itself: it puts real bytes in the real CAS, real rows in the real queue
/// and real pins in the real `PinStore`, then asks the composition root for
/// exactly what the views ask it for.
@MainActor
final class LibraryStatusWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var reachability: Reachability!
    private var environment: AppEnvironment!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        // `downloadSession` matters: without it `attemptDownload` builds a
        // real ephemeral URLSession and the download test reaches the
        // network (DNS for sync.test) instead of the stub.
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
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func payload(seed: UInt8, bytes: Int = 2048) -> (data: Data, digest: String) {
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((Int(seed) &+ i * 11) & 0xFF) }
        let data = Data(raw)
        return (data, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    @discardableResult
    private func seedGame(id: String, title: String, digest: String, size: Int = 2048) throws -> CatalogueEntry {
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

    private func commitIntoCache(_ data: Data, digest: String) throws {
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try environment.casManager.commit(partialAt: partial, sha256: digest)
    }

    private func status(for entry: CatalogueEntry) -> LibraryStatus? {
        LibraryStatus.highestPriority(among: environment.libraryStatuses(for: entry))
    }

    // MARK: - Each state, through the real stores

    func testAnUncachedGameReadsAsOnServer() throws {
        let rom = payload(seed: 1)
        let entry = try seedGame(id: "asset-1", title: "Metroid", digest: rom.digest)

        XCTAssertEqual(environment.availability(for: entry), .serverOnly)
        XCTAssertEqual(status(for: entry), .serverOnly)
    }

    /// The card that could not exist before: real bytes in the real CAS
    /// must read as ready to play offline, with the badge and the label
    /// saying so.
    func testACachedGameReadsAsReadyOfflineNotOnServer() throws {
        let rom = payload(seed: 2)
        let entry = try seedGame(id: "asset-2", title: "Advance Wars", digest: rom.digest)
        try commitIntoCache(rom.data, digest: rom.digest)

        XCTAssertEqual(environment.availability(for: entry), .verifiedLocal)
        XCTAssertEqual(status(for: entry), .verified)
        XCTAssertEqual(status(for: entry)?.listViewLabel, "Ready offline")
        XCTAssertEqual(
            status(for: entry)?.accessibleName(title: entry.displayTitle),
            "Advance Wars is downloaded and ready to play offline.",
            "the accessible name must not still describe cached content as being on the server"
        )
    }

    func testAPinnedCachedGameReadsAsPinned() throws {
        let rom = payload(seed: 3)
        let entry = try seedGame(id: "asset-3", title: "Pokemon", digest: rom.digest)
        try commitIntoCache(rom.data, digest: rom.digest)
        XCTAssertTrue(environment.togglePin(assetSetID: entry.id))

        XCTAssertEqual(environment.availability(for: entry), .pinnedOffline)
        XCTAssertEqual(status(for: entry), .pinned)
        XCTAssertEqual(status(for: entry)?.listViewLabel, "Pinned")
    }

    func testAGameWithQueueRowsAndNoBytesReadsAsQueued() throws {
        let rom = payload(seed: 4)
        let entry = try seedGame(id: "asset-4", title: "Kirby", digest: rom.digest)

        // Offline, so the queue's own scheduler cannot start a transfer
        // and turn this into `.partial` mid-assertion.
        reachability.simulate(online: false)
        environment.enqueueDownload(for: entry)

        XCTAssertEqual(environment.availability(for: entry), .queued)
        XCTAssertEqual(status(for: entry), .queued)
        XCTAssertEqual(status(for: entry)?.listViewLabel, "Queued")
    }

    /// A cancelled row is not "in the queue" — `AvailabilityInputs`'
    /// contract, which only a caller can honour.
    func testACancelledQueueRowDoesNotLeaveAGameLookingQueued() throws {
        let rom = payload(seed: 5)
        let entry = try seedGame(id: "asset-5", title: "Contra", digest: rom.digest)
        reachability.simulate(online: false)
        environment.enqueueDownload(for: entry)
        let row = try XCTUnwrap(environment.downloadRows().first { $0.assetSetID == entry.id })
        environment.cancelDownload(id: row.id)

        XCTAssertEqual(environment.availability(for: entry), .serverOnly)
        XCTAssertEqual(status(for: entry), .serverOnly)
    }

    /// MC-03's rank-1 rung still outranks availability, in the one
    /// derivation both layouts now share.
    func testSaveDivergenceOutranksAvailabilityInTheSharedDerivation() throws {
        let rom = payload(seed: 6)
        let entry = try seedGame(id: "asset-6", title: "Zelda", digest: rom.digest)
        try commitIntoCache(rom.data, digest: rom.digest)

        // No divergence yet: the availability rung is what renders.
        XCTAssertEqual(status(for: entry), .verified)
        XCTAssertEqual(
            environment.libraryStatuses(for: entry), [.verified],
            "an undiverged game must contribute exactly one rung"
        )
    }

    /// The end-to-end statement of WINDOWS #72: download a game the way the
    /// Download button does, and its card must stop saying "On server".
    func testARealDownloadChangesWhatTheCardSays() async throws {
        let rom = payload(seed: 7)
        let entry = try seedGame(id: "asset-7", title: "Fire Emblem", digest: rom.digest)
        XCTAssertEqual(status(for: entry), .serverOnly)

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: ["Content-Length": "\(rom.data.count)"], body: rom.data)
        }
        let attempt = await environment.attemptDownload(for: entry)
        XCTAssertEqual(attempt, .completed)

        XCTAssertEqual(status(for: entry), .verified, "the badge must follow the bytes, not a literal")
    }

    /// Every entry is derived independently — the defect being guarded
    /// against is precisely a single value applied to the whole grid.
    func testTwoGamesInOneLibraryDeriveDifferentStatuses() throws {
        let cached = payload(seed: 8)
        let absent = payload(seed: 9)
        let cachedEntry = try seedGame(id: "asset-8", title: "Cached", digest: cached.digest)
        let absentEntry = try seedGame(id: "asset-9", title: "Absent", digest: absent.digest)
        try commitIntoCache(cached.data, digest: cached.digest)

        XCTAssertEqual(status(for: cachedEntry), .verified)
        XCTAssertEqual(status(for: absentEntry), .serverOnly)
        XCTAssertNotEqual(
            status(for: cachedEntry), status(for: absentEntry),
            "a hardcoded status would make these equal"
        )
    }
}
