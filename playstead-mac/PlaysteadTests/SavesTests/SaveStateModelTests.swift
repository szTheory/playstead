import XCTest
@testable import Playstead

final class SaveStateModelTests: XCTestCase {
    // MARK: - Three orthogonal axes (D-35)

    func testARevisionReportsUploadedCurrentAndRestoredSimultaneously() {
        let state = SaveStateModel.RevisionState(
            revisionID: "r1", durability: .uploaded, isCurrent: true, isRestoredHere: true
        )
        XCTAssertEqual(state.durability, .uploaded)
        XCTAssertTrue(state.isCurrent)
        XCTAssertTrue(state.isRestoredHere)
    }

    func testNoSaveStatusForGameFunctionExistsAnywhereInSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var violations: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Non-comment lines only: this file's own doc comment quotes
            // the forbidden shape as prose, which must not self-trigger.
            let codeLines = source.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
            if codeLines.range(of: #"func saveStatus"#, options: [.regularExpression, .caseInsensitive]) != nil
                || codeLines.range(of: #"SaveStatus\(for:"#, options: [.regularExpression]) != nil {
                violations.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(violations.isEmpty, "forbidden SaveStatus(for:) shape found in \(violations)")
    }

    // MARK: - Durability is monotone

    func testDurabilityOnlyEverMovesForward() {
        XCTAssertTrue(SaveStateModel.isValidDurabilityTransition(from: .localOnly, to: .queued))
        XCTAssertTrue(SaveStateModel.isValidDurabilityTransition(from: .queued, to: .uploaded))
        XCTAssertTrue(SaveStateModel.isValidDurabilityTransition(from: .localOnly, to: .uploaded))
        XCTAssertTrue(SaveStateModel.isValidDurabilityTransition(from: .uploaded, to: .uploaded))

        XCTAssertFalse(SaveStateModel.isValidDurabilityTransition(from: .uploaded, to: .queued))
        XCTAssertFalse(SaveStateModel.isValidDurabilityTransition(from: .uploaded, to: .localOnly))
        XCTAssertFalse(SaveStateModel.isValidDurabilityTransition(from: .queued, to: .localOnly))
    }

    // MARK: - `current` is scoped to (revision, device)

    func testCurrentIsScopedToARevisionAndDevicePairNotTheRevisionAlone() {
        let onDeviceA = SaveStateModel.CurrentPosition(revisionID: "r1", deviceID: "deviceA")
        let onDeviceB = SaveStateModel.CurrentPosition(revisionID: "r1", deviceID: "deviceB")
        XCTAssertNotEqual(onDeviceA, onDeviceB)

        var currentPositions: Set<SaveStateModel.CurrentPosition> = [onDeviceA]
        XCTAssertTrue(currentPositions.contains(onDeviceA))
        XCTAssertFalse(currentPositions.contains(onDeviceB))
        currentPositions.insert(onDeviceB)
        XCTAssertEqual(currentPositions.count, 2, "the same revision is current on one device and not another")
    }

    // MARK: - Provenance is immutable once set

    func testRestoredProvenanceIsImmutableOnceSet() {
        XCTAssertTrue(SaveStateModel.isValidRestoredTransition(from: false, to: true))
        XCTAssertTrue(SaveStateModel.isValidRestoredTransition(from: true, to: true))
        XCTAssertTrue(SaveStateModel.isValidRestoredTransition(from: false, to: false))
        XCTAssertFalse(SaveStateModel.isValidRestoredTransition(from: true, to: false))
    }

    // MARK: - `conflicted` derives from a set of heads, never per-revision

    func testConflictedIsDerivedFromTheHeadSetNotAPerRevisionField() {
        XCTAssertFalse(SaveStateModel.isConflicted(headRevisionIDs: ["r1"]))
        XCTAssertFalse(SaveStateModel.isConflicted(headRevisionIDs: [] as [String]))
        XCTAssertTrue(SaveStateModel.isConflicted(headRevisionIDs: ["r1", "r2"]))
        XCTAssertTrue(SaveStateModel.isConflicted(headRevisionIDs: ["r1", "r2", "r3"]))
    }

    // MARK: - Rollup (D-36)

    func testRollupLocalOnlyHeader() {
        let result = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .localOnly, hasDivergentHeads: false, earlierLocalOnlyCount: 0, title: "Metroid"
        ))
        XCTAssertEqual(result.header, "Latest save is only on this Mac.")
    }

    func testRollupWaitingToCopyHeader() {
        let result = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .queued, hasDivergentHeads: false, earlierLocalOnlyCount: 0, title: "Metroid"
        ))
        XCTAssertEqual(result.header, "Latest save is waiting to copy to your server.")
    }

    func testRollupOnServerHeader() {
        let result = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .uploaded, hasDivergentHeads: false, earlierLocalOnlyCount: 0, title: "Metroid"
        ))
        XCTAssertEqual(result.header, "Latest save is on your server.")
    }

    func testRollupTwoVersionsHeaderWinsOverEveryDurabilityHeader() {
        for durability: SaveDurability? in [nil, .localOnly, .queued, .uploaded] {
            let result = SaveRollup.rollup(for: SaveRollupInput(
                newestDurability: durability, hasDivergentHeads: true, earlierLocalOnlyCount: 0, title: "Metroid"
            ))
            XCTAssertEqual(result.header, "Two versions of your progress.", "durability \(String(describing: durability)) must not win over divergence")
        }
    }

    func testRollupNoRevisionsYieldsNoSavesYetWithBody() {
        let result = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: nil, hasDivergentHeads: false, earlierLocalOnlyCount: 0, title: "Metroid"
        ))
        XCTAssertEqual(result.header, "No saves yet.")
        XCTAssertEqual(result.bodyLine, "Play Metroid and your progress will show up here.")
    }

    func testMutedSecondLineOnlyWhenCountGreaterThanZeroAndNeverAlone() {
        let zero = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .uploaded, hasDivergentHeads: false, earlierLocalOnlyCount: 0, title: "Metroid"
        ))
        XCTAssertNil(zero.mutedSecondLine)
        XCTAssertNotNil(zero.header) // never alone -- always paired with a header

        let one = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .uploaded, hasDivergentHeads: false, earlierLocalOnlyCount: 1, title: "Metroid"
        ))
        XCTAssertEqual(one.mutedSecondLine, "1 earlier version is only on this Mac.")

        let many = SaveRollup.rollup(for: SaveRollupInput(
            newestDurability: .uploaded, hasDivergentHeads: false, earlierLocalOnlyCount: 3, title: "Metroid"
        ))
        XCTAssertEqual(many.mutedSecondLine, "3 earlier versions are only on this Mac.")
    }

    func testRollupNeverEmitsBackedUpOrUsesMin() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Playstead/Saves/SaveRollup.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        // Non-comment lines only: the doc comments above deliberately
        // name the forbidden shape as prose ("never a `min()`", "never
        // 'backed up'"), which must not self-trigger this scan.
        let codeLines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
        XCTAssertFalse(codeLines.lowercased().contains("backed up"))
        XCTAssertFalse(codeLines.range(of: #"min\("#, options: .regularExpression) != nil)
    }

    // MARK: - Readiness Save row (D-37)

    private func makeSaveStateEngine(saveReadiness: @escaping () -> SaveReadinessCase) -> ReadinessEngine {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        try? FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("saves"), withIntermediateDirectories: true)
        return ReadinessEngine(
            cas: CASManager(paths: paths),
            downloadQueue: DownloadQueue(localStore: try! LocalStore(paths: paths)),
            adapterInstallState: { .installed(executablePath: "/usr/bin/true", verified: true) },
            biosRequired: false,
            hasManagedBIOS: { true },
            hasController: { false },
            hasKeyboard: { true },
            saveDirectoryURL: tempRoot.appendingPathComponent("saves"),
            saveReadiness: saveReadiness
        )
    }

    func testSaveRowCanNeverProduceBlockedForAnyInputIncludingTwoDivergentHeads() {
        let allCases: [SaveReadinessCase] = [
            .noSavesYet, .uploadedAndCurrent, .localOnlyExpectedOffline, .localOnlyReachable,
            .serverHasNewer(device: "MacBook Pro", relativeTime: "2 hours ago"), .twoVersions
        ]
        for saveCase in allCases {
            let engine = makeSaveStateEngine(saveReadiness: { saveCase })
            let report = engine.evaluate(assetSetID: "g1", requiredMembers: [])
            let saveCheck = report.checks.first { $0.kind == .saveState }
            XCTAssertNotNil(saveCheck)
            XCTAssertFalse(saveCheck?.outcome.isBlocking ?? true, "\(saveCase) must never be blocking")
        }
    }

    func testBlockerCountIsUnchangedByThePresenceOfTheSaveRow() {
        let readyEngine = makeSaveStateEngine(saveReadiness: { .uploadedAndCurrent })
        let readyReport = readyEngine.evaluate(assetSetID: "g1", requiredMembers: [])
        XCTAssertEqual(readyReport.blockedCount, 0)

        let twoVersionsEngine = makeSaveStateEngine(saveReadiness: { .twoVersions })
        let twoVersionsReport = twoVersionsEngine.evaluate(assetSetID: "g1", requiredMembers: [])
        XCTAssertEqual(twoVersionsReport.blockedCount, 0, "two-versions must not contribute to the blocker count")
    }

    func testTwoVersionsCaseCarriesTheReviewVersionsAction() {
        let engine = makeSaveStateEngine(saveReadiness: { .twoVersions })
        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [])
        let saveCheck = report.checks.first { $0.kind == .saveState }
        XCTAssertEqual(saveCheck?.remedy?.title, "Review versions…")
        XCTAssertEqual(saveCheck?.remedy?.action, .reviewSaveVersions)
        guard case .warning = saveCheck?.outcome else {
            return XCTFail("expected .warning outcome for two-versions")
        }
    }
}
