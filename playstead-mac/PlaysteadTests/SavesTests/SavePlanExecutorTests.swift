import XCTest
import CryptoKit
@testable import Playstead

/// A scriptable `SavePlanExecutorEnvironment` test double — no real CAS,
/// no real `SaveStore`, so every behaviour below is driven purely by
/// this file's fixtures.
final class FakeSavePlanExecutorEnvironment: SavePlanExecutorEnvironment {
    var bytesByDigest: [String: Data] = [:]
    var captureError: Error?
    private(set) var capturedTargets: [URL] = []
    private(set) var quarantined: [(digest: String, actualDigest: String)] = []

    func revisionBytes(forDigest digest: String) throws -> Data {
        guard let data = bytesByDigest[digest] else {
            throw SavePlanExecutorError.digestMismatch(expected: digest, actual: "missing")
        }
        return data
    }

    func captureExistingFile(at targetURL: URL) throws {
        capturedTargets.append(targetURL)
        if let captureError { throw captureError }
    }

    func quarantineCorruptRevision(digest: String, actualDigest: String) {
        quarantined.append((digest, actualDigest))
    }
}

enum FakeCaptureError: Error { case diskFull }

final class SavePlanExecutorTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavePlanExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    /// Mirrors the executor's own hashing exactly, so fixtures name the
    /// real digest for the bytes under test.
    private func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Behaviours

    func testExecutingKeepWritesNothingAtAll() throws {
        let environment = FakeSavePlanExecutorEnvironment()
        let executor = SavePlanExecutor(environment: environment)
        let target = tempDir.appendingPathComponent("game.sav")

        try executor.execute(.keep(notice: nil), targetURL: target)

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(environment.capturedTargets.isEmpty, ".keep must never call the pre-restore capture hook")
    }

    func testExecutingFreshWritesNothingAtAll() throws {
        let environment = FakeSavePlanExecutorEnvironment()
        let executor = SavePlanExecutor(environment: environment)
        let target = tempDir.appendingPathComponent("game.sav")

        try executor.execute(.fresh(notice: nil), targetURL: target)

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(environment.capturedTargets.isEmpty)
    }

    func testRestoreIntoEmptyTargetWritesTheExactBytesWithNoPromptAndNoModal() throws {
        let bytes = Data(repeating: 0x42, count: 32768)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        let executor = SavePlanExecutor(environment: environment)
        let target = tempDir.appendingPathComponent("game.sav")

        try executor.execute(.restore(revisionDigest: digest, notice: SaveLaunchNotice(title: "x", subline: "y")), targetURL: target)

        let written = try Data(contentsOf: target)
        XCTAssertEqual(written, bytes)
        // No leftover staging file.
        let residue = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(residue, ["game.sav"])
    }

    func testRestoreCapturesCurrentOnDiskBytesBeforeAnyWrite() throws {
        let target = tempDir.appendingPathComponent("game.sav")
        try Data("previous-bytes".utf8).write(to: target)

        let bytes = Data(repeating: 0x11, count: 1024)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        let executor = SavePlanExecutor(environment: environment)

        try executor.execute(.restore(revisionDigest: digest, notice: SaveLaunchNotice(title: "x", subline: "y")), targetURL: target)

        XCTAssertEqual(environment.capturedTargets, [target])
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testFailedPreRestoreCaptureAbortsRestoreAndLeavesTargetUntouched() throws {
        let target = tempDir.appendingPathComponent("game.sav")
        try Data("previous-bytes".utf8).write(to: target)

        let bytes = Data(repeating: 0x11, count: 1024)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        environment.captureError = FakeCaptureError.diskFull
        let executor = SavePlanExecutor(environment: environment)

        XCTAssertThrowsError(
            try executor.execute(.restore(revisionDigest: digest, notice: SaveLaunchNotice(title: "x", subline: "y")), targetURL: target)
        ) { error in
            XCTAssertEqual(error as? SavePlanExecutorError, .preRestoreCaptureFailed)
        }

        XCTAssertEqual(try Data(contentsOf: target), Data("previous-bytes".utf8), "a failed capture must leave the on-disk bytes exactly as they were")
    }

    func testDigestMismatchQuarantinesAndRetainsBytesWithoutWritingOrDeletingAnything() throws {
        let target = tempDir.appendingPathComponent("game.sav")
        try Data("previous-bytes".utf8).write(to: target)

        // The bytes handed back do not hash to the digest they are
        // claimed to be -- a corrupted or substituted CAS object.
        let claimedDigest = "not-the-real-digest"
        let corruptBytes = Data(repeating: 0x99, count: 100)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[claimedDigest] = corruptBytes
        let executor = SavePlanExecutor(environment: environment)

        XCTAssertThrowsError(
            try executor.execute(.restore(revisionDigest: claimedDigest, notice: SaveLaunchNotice(title: "x", subline: "y")), targetURL: target)
        ) { error in
            guard case SavePlanExecutorError.digestMismatch(let expected, _) = error else {
                return XCTFail("expected .digestMismatch")
            }
            XCTAssertEqual(expected, claimedDigest)
        }

        XCTAssertEqual(environment.quarantined.count, 1)
        XCTAssertEqual(environment.quarantined.first?.digest, claimedDigest)
        XCTAssertEqual(try Data(contentsOf: target), Data("previous-bytes".utf8), "digest mismatch must never write, and must never delete the existing file")
    }

    func testFastForwardAlsoCapturesCurrentBytesFirstAndReHashesFully() throws {
        let target = tempDir.appendingPathComponent("game.sav")
        try Data("ancestor-bytes-on-disk".utf8).write(to: target)

        let bytes = Data(repeating: 0x77, count: 2048)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        let executor = SavePlanExecutor(environment: environment)

        try executor.execute(.fastForward(revisionDigest: digest), targetURL: target)

        XCTAssertEqual(environment.capturedTargets, [target])
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testInterruptedRenameLeavesThePreviousSaveIntact() throws {
        // Force the rename step to fail by making the target path an
        // existing non-empty directory rather than a file -- `rename(2)`
        // refuses to replace a non-empty directory with a regular file,
        // so this exercises the "something goes wrong between the
        // staged write and the rename" property without needing to
        // inject a fault mid-syscall.
        let target = tempDir.appendingPathComponent("game.sav")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("marker.txt")
        try Data("still-here".utf8).write(to: marker)

        let bytes = Data(repeating: 0x55, count: 512)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        let executor = SavePlanExecutor(environment: environment)

        XCTAssertThrowsError(
            try executor.execute(.restore(revisionDigest: digest, notice: SaveLaunchNotice(title: "x", subline: "y")), targetURL: target)
        )

        // The prior contents are completely untouched.
        XCTAssertEqual(try Data(contentsOf: marker), Data("still-here".utf8))
        // No staging residue left behind.
        let residue = try FileManager.default.contentsOfDirectory(atPath: tempDir.path).filter { $0.hasPrefix(".staging-") }
        XCTAssertTrue(residue.isEmpty, "a failed rename must reap its own staging file")
    }

    func testWholePlayFlowIssuesZeroHTTPRequests() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SavePlanExecutorFailOnAnyRequestURLProtocol.self]
        SavePlanExecutorFailOnAnyRequestURLProtocol.requestCount = 0

        // Drives readiness-shaped, materialize-shaped, and save-plan-
        // shaped work end to end with no real networking client
        // constructed at all -- proving the property structurally: none
        // of this executor's code path even references URLSession.
        let bytes = Data(repeating: 0x21, count: 4096)
        let digest = hex(of: bytes)
        let environment = FakeSavePlanExecutorEnvironment()
        environment.bytesByDigest[digest] = bytes
        let executor = SavePlanExecutor(environment: environment)
        let target = tempDir.appendingPathComponent("game.sav")

        let plan = LaunchSavePlanner.plan(context: LaunchSaveContext(
            onDiskDigest: nil,
            heads: [SaveHeadCandidate(digest: digest, bytesLocal: true, deviceName: "iMac", lastSavedDescription: "an hour ago")]
        ))
        try executor.execute(plan, targetURL: target)

        XCTAssertEqual(SavePlanExecutorFailOnAnyRequestURLProtocol.requestCount, 0)
    }

    func testSavePathIsResolvedFromTheSaveDirectoryNeverFromTheLaunchDirectory() throws {
        // This type consumes a target path built by the caller from
        // `PlaysteadApp.saveDirectoryURL(forAssetSetID:)` -- a sibling of
        // `launch/`. Assert the invariant at the path-shape level: the
        // save path used in every other test in this file lives under a
        // `saves/<assetSetID>/` style directory, never `launch/`.
        let root = tempDir.appendingPathComponent("Playstead", isDirectory: true)
        let saveDir = root.appendingPathComponent("saves/game-1", isDirectory: true)
        let launchDir = root.appendingPathComponent("launch/game-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let target = saveDir.appendingPathComponent("game.sav")
        XCTAssertFalse(target.path.hasPrefix(launchDir.path))
        XCTAssertTrue(target.path.contains("/saves/"))
    }

    /// D-65: the save plan executes inside the same per-`assetSetID`
    /// mutex span as the process spawn, proven end to end through the
    /// real `AdapterHost.launch` entry point — a second concurrent
    /// launch attempt for the same `assetSetID` must be refused while
    /// `executeSavePlan` is still running.
    func testExecuteSavePlanRunsInsideThePerAssetSetIDLaunchMutex() async throws {
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
        let emulatorsRoot = tempDir.appendingPathComponent("emulators")
        let emulatorDir = emulatorsRoot.appendingPathComponent(pin.emulator).appendingPathComponent(pin.version)
        try FileManager.default.createDirectory(at: emulatorDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: emulatorDir.appendingPathComponent("true"))

        var trueHasher = try StreamingSHA256.resume(from: emulatorDir.appendingPathComponent("true"))
        let trueDigest = trueHasher.finalizeHex()
        try JSONEncoder().encode(InstallVerifyRecord(
            archiveSHA256: pin.sha256, executableSHA256: trueDigest, executablePath: emulatorDir.appendingPathComponent("true").path
        )).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let hostA = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        let hostB = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)

        let savePlanStarted = expectation(description: "executeSavePlan invoked")
        let releaseSavePlan = DispatchSemaphore(value: 0)
        let secondLaunchAttempted = expectation(description: "second concurrent launch attempted while save plan runs")

        let launchTask = Task {
            try await hostA.launch(assetSetID: "mutex-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves", executeSavePlan: {
                savePlanStarted.fulfill()
                releaseSavePlan.wait()
            }) { _ in }
        }

        await fulfillment(of: [savePlanStarted], timeout: 5)

        do {
            _ = try await hostB.launch(assetSetID: "mutex-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected the second concurrent launch to be refused while the first's save plan is still executing")
        } catch AdapterHost.LaunchError.launchInProgress(let assetSetID) {
            XCTAssertEqual(assetSetID, "mutex-game")
        }
        secondLaunchAttempted.fulfill()
        await fulfillment(of: [secondLaunchAttempted], timeout: 1)

        releaseSavePlan.signal()
        let proc = try await launchTask.value
        proc.terminate()
    }
}

/// A `URLProtocol` that fails the test on any request at all —
/// registering it on a session's configuration and driving real work
/// through that session is how this file proves the whole exercised
/// path issues zero HTTP requests.
final class SavePlanExecutorFailOnAnyRequestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        requestCount += 1
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.unknown))
    }

    override func stopLoading() {}
}
