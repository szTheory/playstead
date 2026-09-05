import XCTest
import CryptoKit
@testable import Playstead

/// MC-03/MC-04/MC-05/MC-06: proves the divergence badge, the readiness
/// Save row, the escalated panel, and the comparison sheet's resolution
/// path are reachable **from the assembled app's own composition root**,
/// never merely constructible in isolation.
///
/// Mirrors `StorageShellWiringTests`' and `OnlyCopyWiringTests`'
/// discipline: builds the real `AppEnvironment`, drives only
/// `environment.hasUnacknowledgedSaveDivergence(assetSetID:)`,
/// `environment.readinessReport(for:)`, `environment.saveUploadFailureClassification()`,
/// `environment.conflictSides(forAssetSetID:)`, and
/// `environment.resolveSaveDivergence(assetSetID:chosenRevisionID:)` —
/// the exact calls `LibraryShellView`, `GameRowView`, and
/// `ReadinessSheetView` make. Never constructs `StatusSlotView`,
/// `ReadinessEngine`, `OnlyCopyEscalationPanel`, or
/// `ConflictComparisonSheet` directly in this file.
@MainActor
final class SaveSurfaceWiringTests: XCTestCase {
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

    /// A real 64-character lowercase-hex digest derived from `seed` — a
    /// bare placeholder string is not a valid sha256.
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
        return entry
    }

    @discardableResult
    private func seedRevision(
        contentKey: String, revisionID: String, durability: SaveDurability, blobSHA256: String? = nil
    ) throws -> SaveLineRow {
        let line = try environment.saveStore.resolveLine(
            contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-\(contentKey)"
        )
        try environment.saveStore.insertRevision(
            SaveRevisionRow(
                id: revisionID,
                saveLineID: line.id,
                parentRevisionID: nil,
                blobSHA256: blobSHA256 ?? "blob-\(revisionID)",
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

    // MARK: - MC-03: the divergence badge unions into the card's rank-1 rung

    /// Exactly what `LibraryShellView`'s card-grid composition computes
    /// for each `ShelfItem`: `LibraryStatus.forSaveState(conflicted:)`
    /// fed by `environment.hasUnacknowledgedSaveDivergence`.
    func testDivergedLineYieldsTheBadgeThroughTheRealStatusPath() throws {
        let entry = try seedGame(id: "game-1", title: "Metroid Fusion", digest: digest("rom-1"))
        // Two roots on the same line, neither a parent of the other —
        // two current heads, a genuine fork.
        try seedRevision(contentKey: digest("rom-1"), revisionID: "rev-a", durability: .localOnly)
        try seedRevision(contentKey: digest("rom-1"), revisionID: "rev-b", durability: .localOnly)

        let diverged = environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id)
        XCTAssertTrue(diverged)

        let statuses: [LibraryStatus] = [.serverOnly, LibraryStatus.forSaveState(conflicted: diverged)].compactMap { $0 }
        XCTAssertEqual(
            LibraryStatus.highestPriority(among: statuses), .needsAttention,
            "the badge must win the card's existing rank-1 union, never be bypassed by it"
        )
    }

    /// A single, non-diverged head must never raise the badge.
    func testNonDivergedLineYieldsNoBadge() throws {
        let entry = try seedGame(id: "game-2", title: "Zelda", digest: digest("rom-2"))
        try seedRevision(contentKey: digest("rom-2"), revisionID: "rev-a", durability: .localOnly)

        let diverged = environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id)
        XCTAssertFalse(diverged)
        XCTAssertNil(LibraryStatus.forSaveState(conflicted: diverged))

        let statuses: [LibraryStatus] = [.serverOnly, LibraryStatus.forSaveState(conflicted: diverged)].compactMap { $0 }
        XCTAssertEqual(LibraryStatus.highestPriority(among: statuses), .serverOnly)
    }

    /// A fork whose exact head set has already been disposed (chosen or
    /// kept both) must stop raising the badge, even though both heads
    /// remain standing (D-49/D-52).
    func testDisposedForkStopsRaisingTheBadge() throws {
        let entry = try seedGame(id: "game-3", title: "Contra", digest: digest("rom-3"))
        try seedRevision(contentKey: digest("rom-3"), revisionID: "rev-a", durability: .localOnly)
        try seedRevision(contentKey: digest("rom-3"), revisionID: "rev-b", durability: .localOnly)
        XCTAssertTrue(environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id))

        environment.acknowledgeSaveDivergence(assetSetID: entry.id, thisDeviceOrigin: "This Mac")

        XCTAssertFalse(
            environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id),
            "keeping both must mark this exact head set disposed"
        )
    }

    // MARK: - MC-04: the readiness Save row reports real state

    /// `GameRowView` calls `environment.readinessReport(for:)` with no
    /// override — this is that exact call. A game with a committed,
    /// uploaded revision must not report the empty state.
    func testReadinessSaveRowReportsRealStateForAGameWithSavedProgress() throws {
        let entry = try seedGame(id: "game-4", title: "Pokemon", digest: digest("rom-4"))
        try seedRevision(contentKey: digest("rom-4"), revisionID: "rev-a", durability: .uploaded)

        let report = environment.readinessReport(for: entry)
        let saveCheck = try XCTUnwrap(report.checks.first { $0.kind == .saveState })
        XCTAssertNotEqual(
            saveCheck.finding, "No saved progress yet.",
            "a game with committed save progress must never report the empty state"
        )
        XCTAssertEqual(environment.saveReadinessCase(for: entry), .uploadedAndCurrent)
    }

    /// A genuinely empty line must still report the honest empty state —
    /// proving this isn't merely "always something."
    func testReadinessSaveRowReportsEmptyStateOnlyWhenGenuinelyEmpty() throws {
        let entry = try seedGame(id: "game-5", title: "Kirby", digest: digest("rom-5"))

        let report = environment.readinessReport(for: entry)
        let saveCheck = try XCTUnwrap(report.checks.first { $0.kind == .saveState })
        XCTAssertEqual(saveCheck.finding, "No saved progress yet.")
        XCTAssertEqual(environment.saveReadinessCase(for: entry), .noSavesYet)
    }

    /// A diverged line must report `.twoVersions` through the readiness
    /// row too — D-46: divergence never blocks Play.
    func testReadinessSaveRowReportsTwoVersionsForADivergedLine() throws {
        let entry = try seedGame(id: "game-6", title: "Metroid Fusion", digest: digest("rom-6"))
        try seedRevision(contentKey: digest("rom-6"), revisionID: "rev-a", durability: .localOnly)
        try seedRevision(contentKey: digest("rom-6"), revisionID: "rev-b", durability: .localOnly)

        XCTAssertEqual(environment.saveReadinessCase(for: entry), .twoVersions)
        let report = environment.readinessReport(for: entry)
        XCTAssertFalse(report.checks.contains { $0.kind == .saveState && $0.outcome.isBlocking })
    }

    // MARK: - MC-05: the escalated panel never fires for success states

    /// D-40's central rule: an offline queue must never escalate, even
    /// with a genuine only-copy count — this is the real classifier
    /// `ReadinessSheetView`'s production caller reads.
    func testOfflineConditionRendersNoEscalatedPanel() throws {
        let entry = try seedGame(id: "game-7", title: "Metroid Fusion", digest: digest("rom-7"))
        try seedRevision(contentKey: digest("rom-7"), revisionID: "rev-a", durability: .localOnly)
        reachability.simulate(online: false)

        let count = environment.onlyOnThisMacCount(forAssetSetID: entry.id)
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(environment.saveUploadFailureClassification(), .offlineQueue)

        let escalation = OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(
                onlyOnThisMacCount: count, title: entry.displayTitle,
                failureClassification: environment.saveUploadFailureClassification()
            )
        )
        XCTAssertNil(escalation, "an offline queue is the product working, never an escalation")
    }

    /// Reachable and online, with no upload-lane failure signal, must
    /// also render nothing — escalating "no known failure" would be
    /// escalating success.
    func testReachableWithNoFailureSignalRendersNoEscalatedPanel() throws {
        let entry = try seedGame(id: "game-8", title: "Zelda", digest: digest("rom-8"))
        try seedRevision(contentKey: digest("rom-8"), revisionID: "rev-a", durability: .localOnly)

        XCTAssertEqual(environment.saveUploadFailureClassification(), .none)
        let escalation = OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(
                onlyOnThisMacCount: environment.onlyOnThisMacCount(forAssetSetID: entry.id),
                title: entry.displayTitle,
                failureClassification: environment.saveUploadFailureClassification()
            )
        )
        XCTAssertNil(escalation)
    }

    // MARK: - MC-06: the comparison sheet's resolution path is real

    /// The exact data `ReadinessSheetView`'s production caller hands
    /// `ConflictComparisonSheet`.
    func testConflictSidesReflectTheRealCommittedHeads() throws {
        let entry = try seedGame(id: "game-9", title: "Metroid Fusion", digest: digest("rom-9"))
        try seedRevision(contentKey: digest("rom-9"), revisionID: "rev-a", durability: .localOnly, blobSHA256: "blob-a")
        try seedRevision(contentKey: digest("rom-9"), revisionID: "rev-b", durability: .uploaded, blobSHA256: "blob-b")

        let sides = environment.conflictSides(forAssetSetID: entry.id)
        XCTAssertEqual(Set(sides.map(\.id)), ["rev-a", "rev-b"])
        XCTAssertEqual(Set(sides.map(\.digest)), ["blob-a", "blob-b"])
    }

    /// "Continue from this one" — `SaveConflictResolver.chooseSide`
    /// through `environment.resolveSaveDivergence`, exactly what
    /// `ConflictComparisonSheet`'s `onChoose` invokes.
    func testResolvingChoosesASideAndDisposesTheFork() throws {
        let entry = try seedGame(id: "game-10", title: "Contra", digest: digest("rom-10"))
        let line = try seedRevision(contentKey: digest("rom-10"), revisionID: "rev-a", durability: .localOnly)
        try seedRevision(contentKey: digest("rom-10"), revisionID: "rev-b", durability: .localOnly)
        XCTAssertTrue(environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id))

        let result = environment.resolveSaveDivergence(assetSetID: entry.id, chosenRevisionID: "rev-a")
        XCTAssertEqual(result, .chose(origin: "device-1", otherOrigins: ["device-1"]))

        let disposition = environment.saveStore.fetchForkDisposition(saveLineID: line.id)
        XCTAssertEqual(disposition?.chosenRevisionID, "rev-a")
        XCTAssertFalse(
            environment.hasUnacknowledgedSaveDivergence(assetSetID: entry.id),
            "resolving must dispose this exact head set — both heads still stand (D-48/D-49)"
        )
        XCTAssertEqual(
            environment.saveStore.fetchHeads(saveLineID: line.id).map(\.id).sorted(), ["rev-a", "rev-b"],
            "no revision is ever deleted by a resolution"
        )
    }
}
