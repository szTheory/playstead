import XCTest
@testable import Playstead

/// WR-08: the schema UPGRADE path, which no other test can reach.
///
/// Every suite in this project builds a `LocalStore` in a fresh temp
/// directory in `setUp`, so every test sees a database created by today's
/// migrations and none has ever seen one created by yesterday's. That is
/// precisely why WR-08 survived a green 25/25 `OutboxTests` run: the first
/// cut of `outbox_delivered_watermark` was keyed on `created_at TEXT NOT
/// NULL`, `CREATE TABLE IF NOT EXISTS` no-ops against it, and a defensive
/// `ALTER` added the new column while the old `NOT NULL` survived with no
/// default — leaving the column present and the table unwritable.
///
/// The damage was not a silent no-op. `markDone`'s INSERT throws, its
/// transaction rolls back so the delivered row is not deleted, and
/// `OutboxWorker`'s catch-all routes a delivery that actually SUCCEEDED
/// into `markPendingForRetry` until it quarantines.
final class OutboxWatermarkMigrationTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    /// Stand in for a database created by the first cut of this table.
    private func installPreviousWatermarkSchema(on store: LocalStore) throws {
        try store.connection.execute("DROP TABLE IF EXISTS outbox_delivered_watermark;")
        try store.connection.execute(
            """
            CREATE TABLE outbox_delivered_watermark (
                kind TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            );
            """
        )
    }

    func test_aDatabaseCarryingThePreviousWatermarkSchemaStillDeliversAndSupersedes() throws {
        // A database as an earlier build left it.
        let first = try LocalStore(paths: paths)
        try installPreviousWatermarkSchema(on: first)

        // Reopening re-runs migrations — this is the upgrade under test.
        let upgraded = try LocalStore(paths: paths)
        let curationStore = CurationStore(localStore: upgraded)
        let outbox = Outbox(localStore: upgraded, curationStore: curationStore)

        let report = CurationIntent.availabilityReport(
            id: "report-1", entries: [AvailabilityReportEntry(assetSetID: "asset-1")]
        )
        let entry = try outbox.enqueue(report, at: Date(timeIntervalSince1970: 1_700_000_000))
        try outbox.markInFlight(entry.id)

        // One clause per fact: CI keeps file:line and drops assertion text.
        // Pre-fix this throws on the surviving `created_at NOT NULL`.
        XCTAssertNoThrow(try outbox.markDone(entry.id), "a delivery must not fail on an upgraded database")
        XCTAssertTrue(outbox.listAll().isEmpty, "and the delivered row must actually be deleted, not rolled back")
    }

    /// The upgrade must be a one-time event, not something that fires on
    /// every launch. This table is the only thing that remembers a
    /// delivery across a restart, so wiping it at startup would hand
    /// WR-07 straight back for exactly the case it was filed about.
    func test_theWatermarkSurvivesAnOrdinaryRelaunch() throws {
        let store = try LocalStore(paths: paths)
        let outbox = Outbox(localStore: store, curationStore: CurationStore(localStore: store))

        func report(_ id: String, _ asset: String) -> CurationIntent {
            .availabilityReport(id: id, entries: [AvailabilityReportEntry(assetSetID: asset)])
        }

        let older = try outbox.enqueue(report("report-1", "asset-1"), at: Date(timeIntervalSince1970: 1_700_000_000))
        try outbox.markInFlight(older.id)
        let newer = try outbox.enqueue(report("report-2", "asset-2"), at: Date(timeIntervalSince1970: 1_700_000_060))
        try outbox.markInFlight(newer.id)
        try outbox.markDone(newer.id)

        // The app quits and starts again: migrations re-run.
        let relaunched = try LocalStore(paths: paths)
        let afterRelaunch = Outbox(localStore: relaunched, curationStore: CurationStore(localStore: relaunched))

        // One clause per fact: CI keeps file:line and drops assertion text.
        let carried = afterRelaunch.listAll().first { $0.id == older.id }
        XCTAssertNotNil(carried, "the older in-flight row survives the restart, as it must")
        try afterRelaunch.markPendingForRetry(XCTUnwrap(carried), at: Date(timeIntervalSince1970: 1_700_000_120))

        XCTAssertTrue(
            afterRelaunch.listAll().isEmpty,
            "a delivery recorded before the restart must still supersede after it"
        )
    }

    /// The upgrade must also leave the WR-07 behaviour working, not merely
    /// leave the table writable.
    func test_theSupersedeRuleStillHoldsAfterUpgradingFromThePreviousSchema() throws {
        let first = try LocalStore(paths: paths)
        try installPreviousWatermarkSchema(on: first)

        let upgraded = try LocalStore(paths: paths)
        let outbox = Outbox(localStore: upgraded, curationStore: CurationStore(localStore: upgraded))

        func report(_ id: String, _ asset: String) -> CurationIntent {
            .availabilityReport(id: id, entries: [AvailabilityReportEntry(assetSetID: asset)])
        }

        let older = try outbox.enqueue(report("report-1", "asset-1"), at: Date(timeIntervalSince1970: 1_700_000_000))
        try outbox.markInFlight(older.id)
        let newer = try outbox.enqueue(report("report-2", "asset-2"), at: Date(timeIntervalSince1970: 1_700_000_060))
        try outbox.markInFlight(newer.id)
        try outbox.markDone(newer.id)

        try outbox.markPendingForRetry(older, at: Date(timeIntervalSince1970: 1_700_000_120))

        XCTAssertTrue(outbox.listAll().isEmpty, "the watermark must still supersede after an upgrade, not just exist")
    }
}
