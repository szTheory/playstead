import XCTest
import CryptoKit
@testable import Playstead

/// Proves the WINDOWS #37 regression cannot recur silently: that the
/// production Play path (`GameRowView.play()`) actually builds a save
/// plan and passes a non-nil `executeSavePlan` to `AdapterHost.launch`,
/// that a plan requiring a write reaches the executor against the
/// resolved target path, and that a throwing plan prevents the emulator
/// from ever spawning. `SaveRestoreProofTests` (04-13) already proves
/// the executor itself works correctly through `UITestBootstrap` — this
/// file asserts the seam is *used* on the real call site, which is
/// exactly what was missing before this plan.
@MainActor
final class PlayPathSaveWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var environment: AppEnvironment!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        environment = AppEnvironment(
            paths: paths, apiClient: apiClient, reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
    }

    override func tearDownWithError() throws {
        environment = nil
        StubURLProtocol.reset()
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    private func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func entry(id: String = "asset-1", romSHA256: String) -> CatalogueEntry {
        CatalogueEntry(
            id: id, system: "gba", displayTitle: "Test Game", tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: romSHA256, size: 32_768, name: "game.gba")]
        )
    }

    @discardableResult
    private func commitIntoCAS(_ data: Data) throws -> String {
        let digest = hex(of: data)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try environment.casManager.commit(partialAt: partial, sha256: digest)
        return digest
    }

    // MARK: - Source-level regression guard

    /// The literal regression WINDOWS #37 recorded: a call site that
    /// invokes `adapterHost.launch(...)` without passing
    /// `executeSavePlan` at all takes the default `nil`, and no save
    /// plan ever runs. This asserts the production call site both names
    /// the parameter and never spells out a literal `nil` for it.
    func testProductionLaunchCallSitePassesANonNilExecuteSavePlan() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Library/GameRowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let launchCallRange = source.range(of: "try await adapterHost.launch(") else {
            return XCTFail("expected to find the production adapterHost.launch(...) call site")
        }
        let callSiteAndOnward = source[launchCallRange.lowerBound...]
        guard let closingParenRange = callSiteAndOnward.range(of: ") { exit in") else {
            return XCTFail("expected the launch call's argument list to end before its onExit trailing closure")
        }
        let callSite = String(callSiteAndOnward[..<closingParenRange.upperBound])

        XCTAssertTrue(callSite.contains("executeSavePlan:"), "the production call site must name executeSavePlan explicitly")
        XCTAssertFalse(callSite.contains("executeSavePlan: nil"), "the production call site must never pass a literal nil")
    }

    func testGameRowViewSourceNeverReferencesASecondLaunchMutex() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Playstead/Library/GameRowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("AdapterLaunchMutex"), "no second mutex may be introduced -- the plan runs where AdapterHost already invokes it")
    }

    // MARK: - buildSaveLaunchPlan: a write-requiring plan reaches the executor

    func testAWriteRequiringPlanRestoresTheExactBytesAtTheResolvedTargetPath() throws {
        let romSHA256 = String(repeating: "a", count: 64)
        let bytes = Data(repeating: 0x5A, count: 32_768)
        let digest = try commitIntoCAS(bytes)

        let saveStore = SaveStore(localStore: environment.localStore)
        try saveStore.resolveLine(contentKey: romSHA256, saveKind: "battery", slot: "0", placeholderID: "line-1")
        try saveStore.insertRevision(SaveRevisionRow(
            id: "r1", saveLineID: "line-1", parentRevisionID: nil, blobSHA256: digest, sizeBytes: 32_768,
            originDeviceID: "another-mac", deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))

        let saveDir = tempRoot.appendingPathComponent("saves/asset-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let romURL = tempRoot.appendingPathComponent("launch/asset-1/game.gba")

        let testEntry = entry(romSHA256: romSHA256)
        let members = [(sha256: romSHA256, declaredName: "game.gba")]

        let saveLaunch = GameRowView.buildSaveLaunchPlan(
            environment: environment, entry: testEntry, members: members, romURL: romURL, saveDir: saveDir
        )

        guard case .restore = saveLaunch.plan else {
            return XCTFail("expected .restore into an empty target, got \(saveLaunch.plan)")
        }
        XCTAssertEqual(saveLaunch.targetURL, saveDir.appendingPathComponent("game.sav"))
        XCTAssertNotNil(saveLaunch.notice)

        try saveLaunch.executeSavePlan()

        XCTAssertEqual(try Data(contentsOf: saveLaunch.targetURL), bytes)
    }

    func testANoOpPlanForAFirstEverLaunchWritesNothing() throws {
        let romSHA256 = String(repeating: "b", count: 64)
        let saveDir = tempRoot.appendingPathComponent("saves/asset-2", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let romURL = tempRoot.appendingPathComponent("launch/asset-2/game.gba")

        let testEntry = entry(id: "asset-2", romSHA256: romSHA256)
        let members = [(sha256: romSHA256, declaredName: "game.gba")]

        let saveLaunch = GameRowView.buildSaveLaunchPlan(
            environment: environment, entry: testEntry, members: members, romURL: romURL, saveDir: saveDir
        )

        if case .fresh = saveLaunch.plan {} else {
            XCTFail("expected .fresh for a first-ever launch, got \(saveLaunch.plan)")
        }
        try saveLaunch.executeSavePlan()
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveLaunch.targetURL.path))
    }

    // MARK: - A throwing plan prevents the emulator from spawning

    struct FakeSavePlanFailure: Error {}

    /// Drives the exact `AdapterHost.launch(executeSavePlan:onExit:)`
    /// contract `buildSaveLaunchPlan`'s result feeds — proving a throw
    /// aborts the launch before the emulator process is ever spawned
    /// (D-44), and releases the per-assetSetID mutex so a subsequent
    /// launch is not left permanently blocked by the failure.
    func testAThrowingExecuteSavePlanAbortsBeforeTheEmulatorSpawns() async throws {
        let pinJSON = """
        {
          "system": "gba", "emulator": "mgba", "version": "0.10.5",
          "download_url": "https://example.test/mgba.dmg",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000",
          "launch": {"executable_relative_path": "true", "argument_template": []},
          "config_injection": {"mechanism": "cli_config_override", "keys": {"save_directory": "-C savegamePath={path}"}},
          "save_contract": {"artifact_glob": "{saveDir}/{romBaseName}.sav", "directory_key": "savegamePath", "flush_triggers": ["periodic_during_play_observed_every_24s"], "on_demand_flush_supported": false, "worst_case_loss_seconds": 24},
          "exit_detection": {"clean": {"terminationStatus": 0, "terminationReason": "exit"}, "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"}, "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}}
        }
        """
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))
        let emulatorsRoot = tempRoot.appendingPathComponent("emulators")
        let emulatorDir = emulatorsRoot.appendingPathComponent(pin.emulator).appendingPathComponent(pin.version)
        try FileManager.default.createDirectory(at: emulatorDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: emulatorDir.appendingPathComponent("true"))

        var trueHasher = try StreamingSHA256.resume(from: emulatorDir.appendingPathComponent("true"))
        let trueDigest = trueHasher.finalizeHex()
        try JSONEncoder().encode(InstallVerifyRecord(
            archiveSHA256: pin.sha256, executableSHA256: trueDigest, executablePath: emulatorDir.appendingPathComponent("true").path
        )).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let host = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        let exitCalled = expectation(description: "onExit must never fire -- the process never spawned")
        exitCalled.isInverted = true

        do {
            _ = try await host.launch(
                assetSetID: "throwing-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves",
                executeSavePlan: { throw FakeSavePlanFailure() }
            ) { _ in exitCalled.fulfill() }
            XCTFail("expected the throwing executeSavePlan to abort the launch")
        } catch is FakeSavePlanFailure {
            // Expected: the throw propagates and the emulator never spawns.
        }

        await fulfillment(of: [exitCalled], timeout: 0.5)

        // The mutex must have been released by the abort path -- a
        // second launch for the same assetSetID must succeed, not be
        // refused as `.launchInProgress`.
        let proc = try await host.launch(assetSetID: "throwing-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
        proc.terminate()
    }
}
