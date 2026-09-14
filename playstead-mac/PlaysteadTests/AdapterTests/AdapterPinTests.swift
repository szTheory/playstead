import XCTest
@testable import Playstead

final class AdapterPinTests: XCTestCase {

    /// A launch id no other test can collide with.
    ///
    /// `AdapterLaunchMutex.shared` is process-global and keyed by asset-set
    /// id, and its key is released by the spawned process's termination
    /// handler. Five tests across four suites used the literal
    /// "test-asset-set", so ONE launch whose process never exited leaked that
    /// key for the rest of the run and every later test throwing
    /// `launchInProgress` instead of doing its job -- including
    /// InstallerTests' digest-mismatch refusal, whose real assertion was
    /// silently replaced by the wrong error (WINDOWS #86). Unique ids make
    /// that cross-test coupling impossible.
    private func uniqueAssetSetID() -> String { "test-asset-set-\(UUID().uuidString)" }
    /// Mirrors `.planning/phases/03-mac-offline-play-vertical-slice/03-ADAPTER-PIN.json`
    /// exactly, so decode-shape assertions don't depend on bundle
    /// resource resolution during the test run.
    private let pinJSON = """
    {
      "system": "gba",
      "emulator": "mgba",
      "version": "0.10.5",
      "download_url": "https://github.com/mgba-emu/mgba/releases/download/0.10.5/mGBA-0.10.5-macos.dmg",
      "sha256": "443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c",
      "launch": {
        "executable_relative_path": "Contents/MacOS/mGBA",
        "argument_template": ["-C", "savegamePath={saveDir}", "{romPath}"]
      },
      "config_injection": {
        "mechanism": "cli_config_override",
        "keys": {
          "save_directory": "-C savegamePath={path}",
          "bios_path": "-b {path}",
          "controller_mapping": "not_probed_no_hardware_available"
        }
      },
      "save_contract": {
        "artifact_glob": "{saveDir}/{romBaseName}.sav",
        "directory_key": "savegamePath",
        "flush_triggers": ["periodic_during_play_observed_every_24s", "clean_quit_but_sigterm_alone_does_not_trigger_a_graceful_flush_distinct_from_crash"],
        "on_demand_flush_supported": false,
        "worst_case_loss_seconds": 24
      },
      "exit_detection": {
        "clean": [{"terminationStatus": 0, "terminationReason": "exit"}],
        "crash": [{"terminationStatus": 11, "terminationReason": "uncaughtSignal"}],
        "killed": [
          {"terminationStatus": 9, "terminationReason": "uncaughtSignal"},
          {"terminationStatus": 15, "terminationReason": "uncaughtSignal"}
        ]
      }
    }
    """

    func testDecodesAndDigestIs64HexCharacters() throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))

        XCTAssertEqual(pin.system, "gba")
        XCTAssertEqual(pin.emulator, "mgba")
        XCTAssertEqual(pin.version, "0.10.5")
        XCTAssertEqual(pin.sha256.count, 64)
        XCTAssertTrue(pin.sha256.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(pin.launch.executableRelativePath, "Contents/MacOS/mGBA")
    }

    func testArgumentTemplateRendersSubstitutedRomAndSavePaths() throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))
        let rendered = pin.launch.renderedArguments(
            romPath: "/tmp/launch/game.gba",
            saveDir: "/tmp/saves"
        )

        XCTAssertEqual(rendered, ["-C", "savegamePath=/tmp/saves", "/tmp/launch/game.gba"])
        XCTAssertTrue(rendered.contains("/tmp/launch/game.gba"))
    }

    /// Note what this test can and cannot do: it decodes the fixture below
    /// and asserts the classification that fixture describes, so it is
    /// green for any self-consistent pin. That closed loop is why WINDOWS
    /// #76 survived -- see `AdapterExitBoundaryTests`, which classifies
    /// real child-process terminations against the pin that actually
    /// ships.
    func testExitDetectionClassifiesAllThreeKnownSignatures() throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))

        XCTAssertEqual(AdapterExit.classify(status: 0, reason: .exit, against: pin.exitDetection), .clean)
        XCTAssertEqual(AdapterExit.classify(status: 11, reason: .uncaughtSignal, against: pin.exitDetection), .crashed)
        XCTAssertEqual(AdapterExit.classify(status: 9, reason: .uncaughtSignal, against: pin.exitDetection), .killed)
        XCTAssertEqual(
            AdapterExit.classify(status: 42, reason: .exit, against: pin.exitDetection),
            .unknown(status: 42, reason: "exit")
        )
    }

    func testRealBundleResourceDecodesSuccessfully() throws {
        // Proves AdapterPin.json actually ships as a bundle resource and
        // decodes with the app's real Bundle.main, not just the literal
        // fixture above.
        let pin = try AdapterPin.load()
        XCTAssertEqual(pin.emulator, "mgba")
        XCTAssertEqual(pin.sha256.count, 64)
    }

    // MARK: - AdapterHost: refuses launch on digest mismatch

    func testAdapterHostRefusesLaunchOnDigestMismatch() async throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let emulatorDir = tempRoot
            .appendingPathComponent("emulators")
            .appendingPathComponent(pin.emulator)
            .appendingPathComponent(pin.version)
        let executableDir = emulatorDir.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDir, withIntermediateDirectories: true)
        try Data("fake-binary".utf8).write(to: executableDir.appendingPathComponent("mGBA"))

        // The archive this installation came from matched the pin, but
        // the recorded digest of the *expanded executable* deliberately
        // does not match the binary now on disk — the case a live
        // re-hash on every launch exists to catch.
        let mismatchRecord = InstallVerifyRecord(
            archiveSHA256: pin.sha256,
            executableSHA256: String(repeating: "0", count: 64),
            executablePath: executableDir.appendingPathComponent("mGBA").path
        )
        try JSONEncoder().encode(mismatchRecord).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let host = AdapterHost(pin: pin, emulatorsRoot: tempRoot.appendingPathComponent("emulators"))

        do {
            _ = try await host.launch(assetSetID: uniqueAssetSetID(), romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected digestMismatch")
        } catch let error as AdapterHost.LaunchError {
            guard case .digestMismatch = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
        }
    }
}
