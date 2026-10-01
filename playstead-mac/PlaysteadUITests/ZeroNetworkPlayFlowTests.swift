import XCTest
import CoreFoundation

/// Plan 04-13 task 1: the strict zero-network Play flow assertion.
/// Deliberately stricter than the shipped blob-only precedent -- this
/// installs a recording transport for the *entire* Play flow (readiness,
/// materialize, save-plan execution, and adapter spawn, including any
/// detached or fire-and-forget task started along the way) and asserts
/// zero recorded HTTP requests. A post-spawn fetch could not help anyway,
/// because mutating a mmap'd `.sav` under a running emulator is itself
/// corruption.
///
/// A UI test target cannot `@testable import Playstead`, so this test
/// drives the accessible surface `UITestBootstrap.maybeRunZeroNetworkPlayFlowProof`
/// exposes -- one env var naming a result path -- mirroring the existing
/// `SaveEndToEndTests`/`SaveRestoreProofTests` convention.
@MainActor
final class ZeroNetworkPlayFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private var root: URL?

    override func tearDownWithError() throws {
        app?.terminate()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testWholePlayFlowRecordsZeroHTTPRequests() throws {
        let runRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-zero-network-play-flow-\(UUID().uuidString.lowercased())", isDirectory: true)
        root = runRoot
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let resultURL = runRoot.appendingPathComponent("zero-network-play-flow-result.json")

        let launched = XCUIApplication()
        app = launched
        launched.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        launched.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_PROFILE"] = "empty-library"
        launched.launchEnvironment["PLAYSTEAD_UI_TEST_ZERO_NETWORK_PLAY_FLOW_RESULT_PATH"] = resultURL.path
        launched.launch()

        XCTAssertTrue(launched.descendants(matching: .any)["playstead.surface.library"].awaitExistence(timeout: 20))

        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: resultURL.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path), "zero-network-play-flow result was never written within 60s")

        let resultData = try Data(contentsOf: resultURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        let hasClosedSchema = Set(object.keys) == ["recorded_request_count", "failure_stage"]
        XCTAssertTrue(hasClosedSchema, "zero-network Play flow result schema must remain closed")
        guard hasClosedSchema else { return }
        guard let countNumber = object["recorded_request_count"] as? NSNumber,
              CFGetTypeID(countNumber) != CFBooleanGetTypeID() else {
            XCTFail("zero-network Play flow request count has an invalid type")
            return
        }
        let countEncoding = String(cString: countNumber.objCType)
        let countText = countNumber.stringValue
        guard countEncoding != "f", countEncoding != "d",
              !countText.isEmpty,
              countText.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let requestCount = Int(countText) else {
            XCTFail("zero-network Play flow request count has an invalid type")
            return
        }
        let stageValue = object["failure_stage"]
        let allowedStages: Set<String> = [
            "stand-in-signing", "adapter-selection", "synthetic-cas", "catalogue-readiness",
            "materialization-save-setup", "adapter-launch", "adapter-exit", "unclassified",
        ]
        let failureStage: String?
        if stageValue is NSNull {
            failureStage = nil
        } else {
            guard let stage = stageValue as? String else {
                XCTFail("zero-network Play flow failure stage has an invalid type")
                return
            }
            let isAllowed = allowedStages.contains(stage)
            XCTAssertTrue(isAllowed, "zero-network Play flow stage value is invalid")
            failureStage = isAllowed ? stage : nil
        }

        XCTAssertNil(failureStage, failureStage.map { "PLAYSTEAD_ZERO_NETWORK_FAILURE_STAGE[\($0)]" } ?? "")
        XCTAssertEqual(requestCount, 0, "the whole Play flow -- plan, execute, spawn, and any task started along the way -- must attempt zero HTTP requests")
    }
}
