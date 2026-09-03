import XCTest
@testable import Playstead

/// Covers D-63's per-directory backup exclusion boundary: the five
/// reconstructable cache directories are excluded from Time Machine, the
/// root and the irreplaceable `saves/`/`playstead.sqlite3` locations are
/// never excluded, and a stale root-level flag from a pre-D-63 install is
/// cleared idempotently at launch.
final class AppPathsBackupExclusionTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPathsBackupExclusionTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    private func isExcluded(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    // MARK: - Fresh root

    func testFreshRootExcludesTheFiveReconstructableDirectories() {
        let paths = AppPaths(root: tempRoot)

        for dir in [paths.objects, paths.partials, paths.launch, paths.emulators, paths.bios] {
            XCTAssertTrue(isExcluded(dir), "\(dir.lastPathComponent) should be excluded from backup")
        }
    }

    func testFreshRootItselfIsNotExcluded() {
        let paths = AppPaths(root: tempRoot)

        XCTAssertFalse(isExcluded(paths.root), "root must never be excluded from backup (D-63)")
    }

    func testFreshRootSavesAndDatabaseAreNotExcluded() throws {
        let paths = AppPaths(root: tempRoot)

        let saves = paths.root.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.databaseURL.path, contents: Data())

        XCTAssertFalse(isExcluded(saves), "saves/ must remain Time-Machine-eligible (D-63)")
        XCTAssertFalse(isExcluded(paths.databaseURL), "playstead.sqlite3 must remain Time-Machine-eligible (D-63)")
    }

    // MARK: - Existing-install migration

    func testExistingInstallWithStaleRootFlagIsRepairedAtInit() throws {
        // Simulate the pre-D-63 shape: root itself carries the flag.
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        var mutableRoot = tempRoot!
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableRoot.setResourceValues(values)
        XCTAssertTrue(isExcluded(tempRoot), "precondition: stale root flag is set before init")

        let paths = AppPaths(root: tempRoot)

        XCTAssertFalse(isExcluded(paths.root), "stale root flag must be cleared at init")
        for dir in [paths.objects, paths.partials, paths.launch, paths.emulators, paths.bios] {
            XCTAssertTrue(isExcluded(dir), "\(dir.lastPathComponent) should still be excluded after migration")
        }
    }

    // MARK: - Idempotency

    func testClearingTheStaleFlagTwiceIsANoOp() {
        // First init clears any stale flag (none present) and applies
        // exclusion to the five managed directories.
        _ = AppPaths(root: tempRoot)

        // Second init against the same root must leave every flag in
        // the same state.
        let paths = AppPaths(root: tempRoot)

        XCTAssertFalse(isExcluded(paths.root))
        for dir in [paths.objects, paths.partials, paths.launch, paths.emulators, paths.bios] {
            XCTAssertTrue(isExcluded(dir))
        }
    }
}
