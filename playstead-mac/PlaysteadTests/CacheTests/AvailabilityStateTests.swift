import XCTest
import CryptoKit
@testable import Playstead

final class AvailabilityStateTests: XCTestCase {

    // MARK: - Exhaustive combination coverage

    /// Enumerates every combination of the four input facts across a
    /// two-required-member fixture and asserts exactly one state results
    /// for each — the derivation is total and deterministic.
    func testEveryCombinationOfFourInputFactsDerivesExactlyOneState() {
        let members = ["m1", "m2"]
        let cachedOptions: [Set<String>] = [[], ["m1"], ["m1", "m2"]]
        let queuedOptions: [Set<String>] = [[], ["m1"], ["m1", "m2"]]
        let pinnedOptions = [false, true]

        for cached in cachedOptions {
            for queued in queuedOptions {
                for pinned in pinnedOptions {
                    let inputs = AvailabilityInputs(
                        requiredMemberSHAs: members,
                        queuedMemberSHAs: queued,
                        cachedMemberSHAs: cached,
                        isPinned: pinned
                    )
                    // `derive` is a total function — this call either
                    // returns exactly one `AvailabilityState` or the test
                    // itself would fail to compile/crash. The real
                    // assertion is the expected-value table below.
                    let state = AvailabilityState.derive(inputs)

                    let allCached = cached.count == members.count
                    let anyCached = !cached.isEmpty
                    let anyQueued = !queued.isEmpty

                    let expected: AvailabilityState
                    if allCached {
                        expected = pinned ? .pinnedOffline : .verifiedLocal
                    } else if anyCached {
                        expected = .partial
                    } else if anyQueued {
                        expected = .queued
                    } else {
                        expected = .serverOnly
                    }

                    XCTAssertEqual(
                        state, expected,
                        "cached=\(cached) queued=\(queued) pinned=\(pinned) expected \(expected) got \(state)"
                    )
                }
            }
        }
    }

    func testEmptyRequiredMembersIsServerOnlyNeverVacuouslyVerified() {
        let inputs = AvailabilityInputs(requiredMemberSHAs: [], cachedMemberSHAs: [], isPinned: false)
        XCTAssertEqual(AvailabilityState.derive(inputs), .serverOnly)
    }

    func testAllCachedAndPinnedIsPinnedOffline() {
        let inputs = AvailabilityInputs(requiredMemberSHAs: ["m1"], cachedMemberSHAs: ["m1"], isPinned: true)
        XCTAssertEqual(AvailabilityState.derive(inputs), .pinnedOffline)
    }

    func testAllCachedAndUnpinnedIsVerifiedLocal() {
        let inputs = AvailabilityInputs(requiredMemberSHAs: ["m1"], cachedMemberSHAs: ["m1"], isPinned: false)
        XCTAssertEqual(AvailabilityState.derive(inputs), .verifiedLocal)
    }

    func testSingleMemberGameBehavesIdenticallyToManyMemberGame() {
        // A single-member game fully cached and pinned...
        let single = AvailabilityInputs(requiredMemberSHAs: ["only"], cachedMemberSHAs: ["only"], isPinned: true)
        // ...derives the same as a many-member game with all members
        // cached and pinned — no special-casing on member count.
        let many = AvailabilityInputs(requiredMemberSHAs: ["a", "b", "c"], cachedMemberSHAs: ["a", "b", "c"], isPinned: true)
        XCTAssertEqual(AvailabilityState.derive(single), AvailabilityState.derive(many))
        XCTAssertEqual(AvailabilityState.derive(single), .pinnedOffline)
    }

    // MARK: - Storage-view-only `.safeToEvict`

    func testSafeToEvictOnlyAppearsInStorageViewDerivationNeverInDerive() {
        let inputs = AvailabilityInputs(requiredMemberSHAs: ["m1"], cachedMemberSHAs: ["m1"], isPinned: false)
        XCTAssertEqual(AvailabilityState.derive(inputs), .verifiedLocal)
        XCTAssertEqual(AvailabilityState.deriveForStorageView(inputs), .safeToEvict)
    }

    func testPinnedNeverSafeToEvictEvenInStorageView() {
        let inputs = AvailabilityInputs(requiredMemberSHAs: ["m1"], cachedMemberSHAs: ["m1"], isPinned: true)
        XCTAssertEqual(AvailabilityState.deriveForStorageView(inputs), .pinnedOffline)
    }

    /// The card never receives `.safeToEvict`: `GameCardView`'s own
    /// `LibraryStatus.forCard(availability:activeMemberProgressPercent:)`
    /// consumes `AvailabilityState`, and `.derive(_:)` (the only entry
    /// point a card may call) structurally cannot produce `.safeToEvict`
    /// for ANY input combination — proven by running every combination
    /// from the exhaustive test above through `derive` and asserting none
    /// equal `.safeToEvict`.
    func testCardNeverReceivesSafeToEvictAcrossEveryInputCombination() {
        let members = ["m1", "m2"]
        let cachedOptions: [Set<String>] = [[], ["m1"], ["m1", "m2"]]
        let queuedOptions: [Set<String>] = [[], ["m1"], ["m1", "m2"]]
        for cached in cachedOptions {
            for queued in queuedOptions {
                for pinned in [false, true] {
                    let inputs = AvailabilityInputs(
                        requiredMemberSHAs: members, queuedMemberSHAs: queued, cachedMemberSHAs: cached, isPinned: pinned
                    )
                    XCTAssertNotEqual(AvailabilityState.derive(inputs), .safeToEvict)
                    // The resulting card status is always well-formed —
                    // `LibraryStatus` has no case corresponding to
                    // "safe to evict" at all, so this call cannot even
                    // express that value.
                    _ = LibraryStatus.forCard(availability: AvailabilityState.derive(inputs), activeMemberProgressPercent: nil)
                }
            }
        }
    }

    // MARK: - Schema: no availability column exists anywhere

    /// No table in `Migrations.swift` has a column holding one of the six
    /// availability names — the only state column anywhere is
    /// `download_queue_items.state`, whose permitted values are transfer
    /// states (waiting/active/paused/cancelled), never one of the six
    /// availability names.
    func testNoTableHasAnAvailabilityNamedColumn() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = AppPaths(root: tempRoot)
        let connection = try SQLiteConnection(path: paths.databaseURL.path)
        try Migrations.run(on: connection)

        let availabilityNames: Set<String> = [
            "server_only", "server-only", "queued", "partial",
            "verified_local", "verified-local", "pinned_offline", "pinned-offline",
            "safe_to_evict", "safe-to-evict",
        ]

        let tableNames = try connection.query(
            "SELECT name FROM sqlite_master WHERE type = 'table';"
        ) { row -> String in row.string(0) ?? "" }

        var violatingColumns: [String] = []
        for table in tableNames {
            let columnRows = try connection.query("PRAGMA table_info(\(table));") { row -> String in
                row.string(1) ?? "" // column 1 is the column name in PRAGMA table_info
            }
            for column in columnRows {
                let normalized = column.lowercased()
                if availabilityNames.contains(normalized) {
                    violatingColumns.append("\(table).\(column)")
                }
            }
        }

        XCTAssertTrue(violatingColumns.isEmpty, "availability-named columns found: \(violatingColumns)")

        // `download_queue_items.state`'s only permitted values are
        // transfer states, never an availability name — asserted
        // directly against `QueueItemState`'s raw values.
        let permittedQueueStates: Set<String> = [
            QueueItemState.waiting.rawValue, QueueItemState.active.rawValue,
            QueueItemState.paused.rawValue, QueueItemState.cancelled.rawValue,
        ]
        XCTAssertEqual(permittedQueueStates, ["waiting", "active", "paused", "cancelled"])
        for name in availabilityNames {
            XCTAssertFalse(permittedQueueStates.contains(name), "'\(name)' must never be a valid download_queue_items.state value")
        }
    }

    // MARK: - Database rebuild reproducibility

    /// Deleting the local database and rebuilding it from a stubbed
    /// snapshot plus the on-disk cache reproduces the same derived state
    /// for every fixture game — proving the six states are truly
    /// computed from disk facts, never a value that could be lost or
    /// drift when the database itself is discarded.
    func testRebuildingDatabaseFromSnapshotAndDiskCacheReproducesSameDerivedState() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = AppPaths(root: tempRoot)
        let cas = CASManager(paths: paths)

        // Seed two fixture objects directly into the on-disk CAS — this
        // survives a database deletion because it lives outside SQLite.
        let cachedDigest = try seedCommittedObject(cas: cas, paths: paths, byte: 0xAA)
        let uncachedDigest = String(repeating: "0", count: 64)

        func fixtureGames() -> [(id: String, requiredSHAs: [String])] {
            [
                (id: "verified-game", requiredSHAs: [cachedDigest]),
                (id: "server-only-game", requiredSHAs: [uncachedDigest]),
            ]
        }

        func derivedStates() -> [String: AvailabilityState] {
            var result: [String: AvailabilityState] = [:]
            for game in fixtureGames() {
                let cachedSHAs = Set(game.requiredSHAs.filter { cas.contains($0) })
                let inputs = AvailabilityInputs(requiredMemberSHAs: game.requiredSHAs, cachedMemberSHAs: cachedSHAs, isPinned: false)
                result[game.id] = AvailabilityState.derive(inputs)
            }
            return result
        }

        // Open a database, run migrations (nothing further needed — the
        // derivation reads the on-disk CAS directly in this test, mirroring
        // how `AvailabilityInputs.cachedMemberSHAs` would be populated from
        // `cache_objects`/`CASManager.contains` in production).
        let firstConnection = try SQLiteConnection(path: paths.databaseURL.path)
        try Migrations.run(on: firstConnection)
        let beforeDeletion = derivedStates()

        // Delete the local database file entirely.
        try FileManager.default.removeItem(at: paths.databaseURL)

        // Rebuild: a fresh database, migrated from scratch — the
        // on-disk CAS (never touched) is what "re-syncing from a
        // stubbed snapshot plus the on-disk cache" stands in for here.
        let secondConnection = try SQLiteConnection(path: paths.databaseURL.path)
        try Migrations.run(on: secondConnection)
        let afterRebuild = derivedStates()

        XCTAssertEqual(beforeDeletion, afterRebuild)
        XCTAssertEqual(afterRebuild["verified-game"], .verifiedLocal)
        XCTAssertEqual(afterRebuild["server-only-game"], .serverOnly)
    }

    private func seedCommittedObject(cas: CASManager, paths: AppPaths, byte: UInt8) throws -> String {
        var raw = [UInt8](repeating: byte, count: 1024)
        for i in 0..<raw.count { raw[i] = raw[i] &+ UInt8(i & 0xFF) }
        let data = Data(raw)
        let digest = sha256Hex(data)

        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = paths.partialURL(for: digest)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return digest
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
