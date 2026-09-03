import XCTest
@testable import Playstead

/// Covers D-65's per-`assetSetID` launch mutex: two concurrent launches of
/// the same game never both proceed, two different games never contend,
/// an interrupted launch releases its key, and process exit always
/// releases regardless of `AdapterExit` classification.
final class LaunchMutexTests: XCTestCase {

    // MARK: - Mutex primitive, driven directly

    func testSecondAcquisitionForTheSameAssetSetIDFails() {
        let mutex = AdapterLaunchMutex()

        XCTAssertTrue(mutex.tryAcquire(assetSetID: "game-a"))
        XCTAssertFalse(mutex.tryAcquire(assetSetID: "game-a"), "a second acquisition while the first is held must not succeed")

        mutex.release(assetSetID: "game-a")
    }

    func testTwoDifferentAssetSetIDsBothAcquireConcurrently() {
        let mutex = AdapterLaunchMutex()

        XCTAssertTrue(mutex.tryAcquire(assetSetID: "game-a"))
        XCTAssertTrue(mutex.tryAcquire(assetSetID: "game-b"), "the mutex is per-game, not global")

        mutex.release(assetSetID: "game-a")
        mutex.release(assetSetID: "game-b")
    }

    func testReleasingAllowsASubsequentAcquisitionToSucceed() {
        let mutex = AdapterLaunchMutex()

        XCTAssertTrue(mutex.tryAcquire(assetSetID: "game-a"))
        mutex.release(assetSetID: "game-a")

        XCTAssertTrue(mutex.tryAcquire(assetSetID: "game-a"), "a fresh acquisition after release must succeed")

        mutex.release(assetSetID: "game-a")
    }

    func testReleasingAKeyThatIsNotHeldIsANoOp() {
        let mutex = AdapterLaunchMutex()

        // No prior acquisition — must not trap or throw.
        mutex.release(assetSetID: "never-held")

        // The key must still be free afterwards.
        XCTAssertTrue(mutex.tryAcquire(assetSetID: "never-held"))
        mutex.release(assetSetID: "never-held")
    }

    // MARK: - AdapterHost.launch wiring

    /// A launch that throws after mutex acquisition but before spawn
    /// (here: `verifyInstalledDigest` failing because nothing is
    /// installed) must release the mutex, so the next launch attempt for
    /// that same game succeeds rather than being permanently refused.
    func testInterruptedLaunchBeforeSpawnReleasesTheMutex() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchMutexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let pin = try AdapterPin.load()
        let host = AdapterHost(pin: pin, emulatorsRoot: tempRoot.appendingPathComponent("emulators"))

        // No install recorded, so `verifyInstalledDigest` throws before
        // any process is spawned — the mutex must still be released.
        do {
            _ = try await host.launch(assetSetID: "interrupted-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected launch to throw before spawn")
        } catch is AdapterHost.LaunchError {
            // expected
        }

        let mutex = AdapterLaunchMutex.shared
        XCTAssertTrue(
            mutex.tryAcquire(assetSetID: "interrupted-game"),
            "the mutex must have been released by the failed launch, not stranded"
        )
        mutex.release(assetSetID: "interrupted-game")
    }

    /// A second concurrent launch attempt for one `assetSetID` must be
    /// refused with `.launchInProgress` while a different `assetSetID`
    /// proceeds — proven end-to-end through the real `AdapterHost.launch`
    /// entry point using a real, held-open child process.
    func testSecondConcurrentLaunchForSameAssetSetIDIsRefusedWhileADifferentOneProceeds() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchMutexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // A long-lived executable (`sleep`) so the first launch's process
        // is still running when the second launch attempt races it.
        let pinJSON = """
        {
          "system": "gba", "emulator": "mgba", "version": "0.10.5",
          "download_url": "https://example.test/mgba.dmg",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000",
          "launch": {"executable_relative_path": "sleep", "argument_template": ["5"]},
          "config_injection": {"mechanism": "cli_config_override", "keys": {"save_directory": "-C savegamePath={path}"}},
          "save_contract": {"artifact_glob": "{saveDir}/{romBaseName}.sav", "directory_key": "savegamePath", "flush_triggers": ["periodic_during_play_observed_every_24s"], "on_demand_flush_supported": false, "worst_case_loss_seconds": 24},
          "exit_detection": {"clean": {"terminationStatus": 0, "terminationReason": "exit"}, "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"}, "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}}
        }
        """
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))
        let emulatorsRoot = tempRoot.appendingPathComponent("emulators")
        let emulatorDir = emulatorsRoot.appendingPathComponent(pin.emulator).appendingPathComponent(pin.version)
        try FileManager.default.createDirectory(at: emulatorDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: emulatorDir.appendingPathComponent("sleep"))

        var sleepHasher = try StreamingSHA256.resume(from: emulatorDir.appendingPathComponent("sleep"))
        let sleepDigest = sleepHasher.finalizeHex()
        try JSONEncoder().encode(InstallVerifyRecord(
            archiveSHA256: pin.sha256, executableSHA256: sleepDigest, executablePath: emulatorDir.appendingPathComponent("sleep").path
        )).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let hostA = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        let hostB = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        let hostC = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)

        let firstExited = expectation(description: "first process exits")
        let proc = try await hostA.launch(assetSetID: "shared-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in
            firstExited.fulfill()
        }
        defer { proc.terminate() }

        // Second launch of the SAME assetSetID must be refused while the
        // first is still running.
        do {
            _ = try await hostB.launch(assetSetID: "shared-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected the second concurrent launch to be refused")
        } catch AdapterHost.LaunchError.launchInProgress(let assetSetID) {
            XCTAssertEqual(assetSetID, "shared-game")
        }

        // A DIFFERENT assetSetID must proceed even while the first is running.
        let secondExited = expectation(description: "second (different game) process exits")
        let procC = try await hostC.launch(assetSetID: "other-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in
            secondExited.fulfill()
        }

        procC.terminate()
        await fulfillment(of: [secondExited], timeout: 5)

        proc.terminate()
        await fulfillment(of: [firstExited], timeout: 5)
    }

    /// The mutex releases when the spawned process exits, regardless of
    /// which `AdapterExit` case that exit classifies as (D-05) — proven
    /// here via a clean (`exit 0`) termination.
    func testMutexReleasesOnProcessExitRegardlessOfExitClassification() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchMutexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

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
        let exited = expectation(description: "process exits cleanly")
        _ = try await host.launch(assetSetID: "clean-exit-game", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { exit in
            XCTAssertEqual(exit, .clean)
            exited.fulfill()
        }
        await fulfillment(of: [exited], timeout: 5)

        let mutex = AdapterLaunchMutex.shared
        XCTAssertTrue(
            mutex.tryAcquire(assetSetID: "clean-exit-game"),
            "the mutex must be released once the process has exited"
        )
        mutex.release(assetSetID: "clean-exit-game")
    }
}
