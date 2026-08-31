import XCTest
@testable import Playstead

final class AdapterPinTests: XCTestCase {
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
        "clean": {"terminationStatus": 15, "terminationReason": "uncaughtSignal"},
        "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"},
        "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}
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

    func testExitDetectionClassifiesAllThreeKnownSignatures() throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))

        XCTAssertEqual(AdapterExit.classify(status: 15, reason: .uncaughtSignal, against: pin.exitDetection), .clean)
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

        // Recorded install-time digest deliberately does not match the pin.
        let mismatchRecord = InstallVerifyRecord(sha256: String(repeating: "0", count: 64))
        try JSONEncoder().encode(mismatchRecord).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let host = AdapterHost(pin: pin, emulatorsRoot: tempRoot.appendingPathComponent("emulators"))

        do {
            _ = try await host.launch(romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected digestMismatch")
        } catch let error as AdapterHost.LaunchError {
            guard case .digestMismatch = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
        }
    }
}
