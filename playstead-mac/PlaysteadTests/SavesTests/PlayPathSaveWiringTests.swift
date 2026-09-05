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

    /// The 04-19 counterpart, and the falsification lever for this
    /// plan: delete the `begin(...)` call from `play()` and this test
    /// must go red. A capture lifecycle that exists and is never
    /// started is exactly the WINDOWS #45 defect -- the component
    /// passes its own unit tests either way, so only an assertion
    /// against the call site itself can catch its removal.
    func testProductionPlayPathBeginsAndEndsACaptureSession() throws {
        let source = try gameRowViewSource()

        guard let playRange = source.range(of: "private func play() async {") else {
            return XCTFail("expected to find the production play() method")
        }
        let play = String(source[playRange.lowerBound...])

        guard let beginRange = play.range(of: "?.begin()") else {
            return XCTFail("play() must open a capture session -- SaveCapturePoller is otherwise never started in production")
        }
        guard let launchRange = play.range(of: "try await adapterHost.launch(") else {
            return XCTFail("expected to find the production adapterHost.launch(...) call site")
        }
        XCTAssertTrue(
            beginRange.lowerBound < launchRange.lowerBound,
            "begin() must run before the emulator spawns, so D-04's session-start baseline sees the artifact as the user left it"
        )

        guard let endRange = play.range(of: "?.end()", range: launchRange.upperBound..<play.endIndex) else {
            return XCTFail("the onExit closure must close the capture session -- nothing else promotes the session's revision")
        }
        guard let recorderRange = play.range(of: "environment.playSessionRecorder.ended(sessionID)") else {
            return XCTFail("expected the onExit closure's existing session-recording call")
        }
        XCTAssertTrue(
            endRange.lowerBound < recorderRange.lowerBound,
            "end() must run before the session is recorded as ended"
        )

        XCTAssertTrue(
            play.contains("buildSaveCaptureCoordinator"),
            "play() must build the coordinator through the tested static seam, never inline the lifecycle"
        )
    }

    /// The launch-time crash-recovery half (WINDOWS #46): the shipped
    /// app must construct `SaveSessionRecovery` somewhere, and the only
    /// legitimate somewhere is app launch.
    func testProductionAppLaunchRunsSaveSessionRecovery() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Playstead/App/PlaysteadApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SaveSessionRecovery(saveStore:"), "SaveSessionRecovery must be constructed in production")
        XCTAssertTrue(
            source.contains(".task { await appEnvironment.recoverAbandonedSaveSessionsAtLaunch() }"),
            "the production root view must actually run the replay pass at launch"
        )
    }

    private func gameRowViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Playstead/Library/GameRowView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
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

    // MARK: - buildSaveCaptureCoordinator: the capture half is wired

    /// The binding that matters: the coordinator captures from the
    /// exact same artifact path the save plan restores into. Two
    /// independently-derived paths would mean the app restores one file
    /// and captures another -- silently, and only in production.
    func testTheCaptureCoordinatorIsBoundToTheSamePathTheSavePlanWrites() throws {
        let romSHA256 = String(repeating: "c", count: 64)
        let saveDir = tempRoot.appendingPathComponent("saves/asset-3", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let romURL = tempRoot.appendingPathComponent("launch/asset-3/game.gba")
        let testEntry = entry(id: "asset-3", romSHA256: romSHA256)
        let members = [(sha256: romSHA256, declaredName: "game.gba")]

        let saveLaunch = GameRowView.buildSaveLaunchPlan(
            environment: environment, entry: testEntry, members: members, romURL: romURL, saveDir: saveDir
        )
        let capture = try XCTUnwrap(GameRowView.buildSaveCaptureCoordinator(
            environment: environment, entry: testEntry, members: members, targetURL: saveLaunch.targetURL
        ))

        XCTAssertEqual(capture.targetURL, saveLaunch.targetURL)
        XCTAssertEqual(capture.artifactRelativePath, "game.sav")

        // Bound to the line keyed by the ROM's own sha256 (D-10), which
        // this call also created -- a first-ever play session must have
        // somewhere to record its promotion.
        let line = try XCTUnwrap(environment.saveStore.fetchLine(contentKey: romSHA256, saveKind: "battery", slot: "0"))
        XCTAssertEqual(capture.saveLineID, line.id)

        // Captures must never land inside the adapter's own declared
        // artifact directory.
        XCTAssertNotEqual(capture.destinationDirectory, saveDir)
        XCTAssertFalse(capture.destinationDirectory.path.hasPrefix(saveDir.path))
    }

    /// SAVE-01, at the seam the shipped Play path actually uses: a
    /// session that writes save bytes leaves a promoted, local-only
    /// revision in the app's own `SaveStore`.
    func testAFullSessionThroughTheProductionSeamPromotesARevisionIntoTheAppsSaveStore() async throws {
        let romSHA256 = String(repeating: "e", count: 64)
        let saveDir = tempRoot.appendingPathComponent("saves/asset-5", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let romURL = tempRoot.appendingPathComponent("launch/asset-5/game.gba")
        let testEntry = entry(id: "asset-5", romSHA256: romSHA256)
        let members = [(sha256: romSHA256, declaredName: "game.gba")]

        let saveLaunch = GameRowView.buildSaveLaunchPlan(
            environment: environment, entry: testEntry, members: members, romURL: romURL, saveDir: saveDir
        )
        let capture = try XCTUnwrap(GameRowView.buildSaveCaptureCoordinator(
            environment: environment, entry: testEntry, members: members, targetURL: saveLaunch.targetURL
        ))

        await capture.begin()
        let played = Data(repeating: 0x7E, count: 512)
        try played.write(to: capture.targetURL)
        await capture.end()

        let promoted = environment.saveStore.fetchRevisions(saveLineID: capture.saveLineID)
            .filter { $0.tier == SaveCaptureTier.promoted.rawValue }
        XCTAssertEqual(promoted.count, 1, "exactly one promoted revision per session (D-04)")
        XCTAssertEqual(promoted.first?.blobSHA256, hex(of: played))
        XCTAssertEqual(promoted.first?.durability, SaveDurability.localOnly.rawValue)
        XCTAssertEqual(environment.onlyOnThisMacCount(forAssetSetID: "asset-5"), 0, "no catalogue entry yet, so no rollup")
    }

    /// A capture that cannot be written must not stop the game
    /// launching: `begin()` on an unwritable capture directory still
    /// lets `AdapterHost.launch` spawn the emulator (D-31 -- the
    /// emulator keeps running; only the durable local capture path is
    /// affected).
    func testACaptureFailureDoesNotPreventTheEmulatorSpawning() async throws {
        let line = try environment.saveStore.resolveLine(
            contentKey: String(repeating: "f", count: 64), saveKind: "battery", slot: "0", placeholderID: "line-blocked"
        )
        let coordinator = environment.makeSaveSessionCoordinator()
        let capture = SaveCaptureWiring(
            coordinator: coordinator,
            saveLineID: line.id,
            targetURL: tempRoot.appendingPathComponent("saves/asset-6/game.sav"),
            // `/dev/null` is a character device, so no capture directory
            // can be created beneath it -- every durable write fails.
            destinationDirectory: URL(fileURLWithPath: "/dev/null/save-captures"),
            artifactRelativePath: "game.sav"
        )

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("saves/asset-6"), withIntermediateDirectories: true
        )
        try Data(repeating: 0x01, count: 64).write(to: capture.targetURL)

        await capture.begin()

        let host = try makeAdapterHost()
        let proc = try await host.launch(assetSetID: "blocked-capture", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
        XCTAssertNotNil(proc, "a blocked capture must never refuse the launch")
        proc.terminate()

        await capture.end()
        XCTAssertTrue(
            environment.saveStore.fetchRevisions(saveLineID: line.id).isEmpty,
            "a capture that could not be written must never record a revision claiming it was"
        )
    }

    // MARK: - D-07 crash recovery at app launch

    /// WINDOWS #46: a session Playstead died in the middle of leaves a
    /// `staged` row with no `promoted` row. App launch must replay it.
    func testAppLaunchReplaysAnAbandonedSessionAndPromotesIt() async throws {
        let romSHA256 = String(repeating: "1", count: 64)
        let testEntry = entry(id: "asset-7", romSHA256: romSHA256)
        try environment.catalogueStore.upsert(testEntry)

        let saveDir = try environment.saveDirectoryURL(forAssetSetID: "asset-7")
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let targetURL = SaveCapturePaths.targetURL(saveDirectory: saveDir, romFileName: "game.gba")
        let bytes = Data(repeating: 0x3C, count: 256)
        try bytes.write(to: targetURL)

        let line = try environment.saveStore.resolveLine(
            contentKey: romSHA256, saveKind: "battery", slot: "0", placeholderID: "line-7"
        )
        try environment.saveStore.insertRevision(SaveRevisionRow(
            id: "staged-7", saveLineID: line.id, parentRevisionID: nil, blobSHA256: hex(of: bytes),
            sizeBytes: 256, originDeviceID: nil, deviceCapturedAt: nil, recordedAt: nil,
            captureMethod: "session", adapterID: nil, adapterVersion: nil, saveFormat: nil,
            formatConfidence: nil, playSessionID: "crashed-session",
            durability: SaveDurability.localOnly.rawValue, localPath: nil,
            tier: SaveCaptureTier.staged.rawValue, origin: SaveCaptureOrigin.session.rawValue,
            manifestDigest: nil, sessionID: "crashed-session"
        ))

        await environment.recoverAbandonedSaveSessionsAtLaunch()

        let promoted = environment.saveStore.fetchRevisions(saveLineID: line.id)
            .filter { $0.tier == SaveCaptureTier.promoted.rawValue }
        XCTAssertEqual(promoted.count, 1, "the abandoned session must be replayed and promoted exactly once")
        XCTAssertEqual(promoted.first?.blobSHA256, hex(of: bytes))
        XCTAssertEqual(promoted.first?.captureMethod, "recovery")
        XCTAssertEqual(promoted.first?.sessionID, "crashed-session")
    }

    /// Replay is idempotent by digest (D-07), so the guarded second
    /// pass -- and an unguarded one -- must both add nothing.
    func testASecondRecoveryPassPromotesNothingNew() async throws {
        try await testAppLaunchReplaysAnAbandonedSessionAndPromotesIt()
        await environment.recoverAbandonedSaveSessionsAtLaunch()

        let promoted = environment.saveStore.fetchRevisions(saveLineID: "line-7")
            .filter { $0.tier == SaveCaptureTier.promoted.rawValue }
        XCTAssertEqual(promoted.count, 1)
    }

    /// The signed-stand-in `AdapterHost` both launch tests drive: a real
    /// pin whose executable is `/usr/bin/true`, with the
    /// `.install-verify.json` sidecar launch re-hashes against.
    private func makeAdapterHost() throws -> AdapterHost {
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

        return AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
    }

    // MARK: - A throwing plan prevents the emulator from spawning

    struct FakeSavePlanFailure: Error {}

    /// Drives the exact `AdapterHost.launch(executeSavePlan:onExit:)`
    /// contract `buildSaveLaunchPlan`'s result feeds — proving a throw
    /// aborts the launch before the emulator process is ever spawned
    /// (D-44), and releases the per-assetSetID mutex so a subsequent
    /// launch is not left permanently blocked by the failure.
    func testAThrowingExecuteSavePlanAbortsBeforeTheEmulatorSpawns() async throws {
        let host = try makeAdapterHost()
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
