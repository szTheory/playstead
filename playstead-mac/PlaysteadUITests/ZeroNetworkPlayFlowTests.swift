import XCTest

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
        let result = try JSONDecoder().decode(ZeroNetworkPlayFlowResult.self, from: resultData)

        XCTAssertNil(result.failureReason, "the in-process Play flow must complete without error: \(result.failureReason ?? "")")
        XCTAssertEqual(result.recordedRequestCount, 0, "the whole Play flow -- plan, execute, spawn, and any task started along the way -- must attempt zero HTTP requests")
    }

    private struct ZeroNetworkPlayFlowResult: Decodable {
        let recordedRequestCount: Int
        let failureReason: String?

        enum CodingKeys: String, CodingKey {
            case recordedRequestCount = "recorded_request_count"
            case failureReason = "failure_reason"
        }
    }
}
