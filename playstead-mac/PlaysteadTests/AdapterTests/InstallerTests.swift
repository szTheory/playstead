import XCTest
import CryptoKit
@testable import Playstead

final class InstallerTests: XCTestCase {
    private var tempRoot: URL!
    private var emulatorsRoot: URL!
    private var localStore: LocalStore!
    private var pin: AdapterPin!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        emulatorsRoot = tempRoot.appendingPathComponent("emulators", isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.pinJSON.utf8))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private static let pinJSON = """
    {
      "system": "gba",
      "emulator": "mgba",
      "version": "0.10.5",
      "download_url": "https://example.invalid/archive.dmg",
      "sha256": "a435f6806bfd6c55ab979fd306a74ee2edf49308e7137a1527931249c43d31e0",
      "launch": {
        "executable_relative_path": "Contents/MacOS/mGBA",
        "argument_template": ["-C", "savegamePath={saveDir}", "{romPath}"]
      },
      "config_injection": {
        "mechanism": "cli_config_override",
        "keys": {"save_directory": "-C savegamePath={path}", "bios_path": "-b {path}", "controller_mapping": "not_probed_no_hardware_available"}
      },
      "save_contract": {
        "artifact_glob": "{saveDir}/{romBaseName}.sav",
        "directory_key": "savegamePath",
        "flush_triggers": ["periodic_during_play_observed_every_24s"],
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

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes a fixture archive whose SHA-256 matches `pin.sha256` exactly,
    /// so an installer under test can be driven through a genuine
    /// digest-match install without any real network or disk-image tool.
    private func writeMatchingArchive() throws -> URL {
        // The pin's fixture digest above is the SHA-256 of this exact
        // 10-byte payload — computed once via `shasum -a 256` and pinned
        // as a literal so the test never needs to compute-then-assert
        // its own input.
        let bytes = Data("archive123".utf8)
        precondition(sha256Hex(bytes) == pin.sha256, "fixture payload must hash to the pinned digest")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        return url
    }

    /// A fake `archiveExpander` that never touches `hdiutil`/`ditto` —
    /// it just materializes a plausible `.app/Contents/MacOS/<exe>`
    /// structure directly under `destinationDir`, with a counter so tests
    /// can assert it was (or wasn't) invoked a second time.
    private final class FakeExpander {
        private(set) var invocationCount = 0
        private let executableRelativePath: String

        init(executableRelativePath: String) {
            self.executableRelativePath = executableRelativePath
        }

        func expand(archiveURL: URL, destinationDir: URL) throws -> URL {
            invocationCount += 1
            let appURL = destinationDir.appendingPathComponent("Fake.app", isDirectory: true)
            let execDir = appURL.appendingPathComponent(executableRelativePath, isDirectory: false).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: execDir, withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: appURL.appendingPathComponent(executableRelativePath))
            return appURL
        }
    }

    // MARK: - Digest mismatch leaves no files

    func testInstallWithWrongDigestLeavesNoFilesAndReturnsTypedMismatchError() async throws {
        let wrongArchive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not-the-right-bytes".utf8).write(to: wrongArchive)

        let expander = FakeExpander(executableRelativePath: pin.launch.executableRelativePath)
        let installer = AdapterInstaller(
            pin: pin, emulatorsRoot: emulatorsRoot, localStore: localStore,
            downloadArchive: { _ in wrongArchive },
            archiveExpander: expander.expand
        )

        do {
            _ = try await installer.install()
            XCTFail("expected digestMismatch")
        } catch let error as AdapterInstallError {
            guard case .digestMismatch(let expected, let actual) = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
            XCTAssertEqual(expected, pin.sha256)
            XCTAssertNotEqual(actual, pin.sha256)
        }

        XCTAssertEqual(expander.invocationCount, 0, "expansion must never run before the digest is confirmed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: emulatorsRoot.path), "no directory must be created under emulators/ on a digest mismatch")
        XCTAssertEqual(installationCount(), 0)
    }

    // MARK: - Idempotent repeat install

    func testSecondInstallWithExistingMatchingInstallationCreatesNoSecondDirectoryOrRecord() async throws {
        let expander = FakeExpander(executableRelativePath: pin.launch.executableRelativePath)
        let installer = AdapterInstaller(
            pin: pin, emulatorsRoot: emulatorsRoot, localStore: localStore,
            downloadArchive: { _ in try self.writeMatchingArchive() },
            archiveExpander: expander.expand
        )

        let first = try await installer.install()
        XCTAssertTrue(first.verified)
        XCTAssertEqual(expander.invocationCount, 1)
        XCTAssertEqual(installationCount(), 1)

        let second = try await installer.install()
        XCTAssertEqual(second, first)
        XCTAssertEqual(expander.invocationCount, 1, "a matching existing installation must not be re-expanded")
        XCTAssertEqual(installationCount(), 1, "no second record must be created")
    }

    // MARK: - Concurrency

    func testTwoConcurrentInstallCallsResultInExactlyOneInstallationRecord() async throws {
        let expander = FakeExpander(executableRelativePath: pin.launch.executableRelativePath)
        let installer = AdapterInstaller(
            pin: pin, emulatorsRoot: emulatorsRoot, localStore: localStore,
            downloadArchive: { _ in try self.writeMatchingArchive() },
            archiveExpander: expander.expand
        )

        async let first = installer.install()
        async let second = installer.install()
        _ = try await (first, second)

        XCTAssertEqual(installationCount(), 1, "two concurrent installs must converge on exactly one record")
    }

    // MARK: - Selecting an existing installation

    func testSelectingExistingInstallationWithMismatchedDigestRecordsUnverifiedAndCardRendersLabel() async throws {
        let selectedRoot = tempRoot.appendingPathComponent("user-selected", isDirectory: true)
        let appURL = selectedRoot.appendingPathComponent("Other.app", isDirectory: true)
        let execDir = appURL.appendingPathComponent(pin.launch.executableRelativePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: execDir, withIntermediateDirectories: true)
        try Data("a completely different build".utf8).write(to: appURL.appendingPathComponent(pin.launch.executableRelativePath))

        let installer = AdapterInstaller(pin: pin, emulatorsRoot: emulatorsRoot, localStore: localStore)
        let selected = try await installer.selectExisting(appURL: appURL)

        XCTAssertFalse(selected.verified)
        XCTAssertNotEqual(selected.sha256, pin.sha256)
        XCTAssertEqual(installationCount(), 1)

        let catalog = AdapterCatalog(pin: pin)
        let card = AdapterCapabilityCard(
            descriptor: catalog.descriptor,
            installState: .installed(executablePath: selected.executablePath, verified: selected.verified)
        )
        XCTAssertTrue(card.installationLabelText.lowercased().contains("unverified"))
    }

    // MARK: - AdapterHost refuses launch against an unverified selection

    func testAdapterHostRefusesLaunchWhenInstallStateIsUnverified() async throws {
        let host = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        await host.setInstallState(.installed(executablePath: "/tmp/does-not-matter", verified: false))

        do {
            _ = try await host.launch(romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("expected digestMismatch")
        } catch let error as AdapterHost.LaunchError {
            guard case .digestMismatch = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
        }
    }

    // MARK: - Capability card renders every descriptor fact

    func testCapabilityCardRendersEverySourcedFact() {
        let catalog = AdapterCatalog(pin: pin)
        let card = AdapterCapabilityCard(descriptor: catalog.descriptor, installState: .notInstalled)

        XCTAssertTrue(card.renderedText.contains(pin.system.uppercased()))
        XCTAssertTrue(card.renderedText.contains(pin.emulator))
        XCTAssertTrue(card.renderedText.contains(pin.version))
        XCTAssertTrue(card.renderedText.contains(pin.sha256))
        XCTAssertTrue(card.renderedText.lowercased().contains("bios"))
        XCTAssertTrue(card.renderedText.lowercased().contains("save"))
    }

    // MARK: - Source-level prohibitions (mirrors this task's own acceptance-criteria grep)

    func testAdapterSourceFilesNameNoSpecificEmulatorCandidate() throws {
        let pattern = try NSRegularExpression(pattern: "mgba|retroarch|sameboy|gambatte|snes9x", options: [.caseInsensitive])
        for path in adapterSourcePaths(named: ["AdapterCatalog.swift", "AdapterInstaller.swift", "AdapterCapabilityCard.swift"]) {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let matches = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
            XCTAssertTrue(matches.isEmpty, "\(path) must name no specific emulator candidate literally")
        }
    }

    func testAdapterDirectoryNeverRemovesQuarantineAttribute() throws {
        let source = try String(contentsOfFile: adapterSourcePaths(named: ["AdapterInstaller.swift"])[0], encoding: .utf8)
        XCTAssertFalse(source.contains("xattr"), "AdapterInstaller.swift must never call xattr / strip quarantine")
    }

    // MARK: - Helpers

    private func installationCount() -> Int {
        let rows = (try? localStore.connection.query("SELECT COUNT(*) FROM adapter_installations;") { $0.int(0) ?? 0 }) ?? [0]
        return rows.first ?? 0
    }

    private func adapterSourcePaths(named names: [String]) -> [String] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let playsteadMacRoot = thisFile
            .deletingLastPathComponent() // InstallerTests.swift -> AdapterTests/
            .deletingLastPathComponent() // AdapterTests/ -> PlaysteadTests/
            .deletingLastPathComponent() // PlaysteadTests/ -> playstead-mac/
        let adapterDir = playsteadMacRoot.appendingPathComponent("Playstead/Adapter")
        return names.map { adapterDir.appendingPathComponent($0).path }
    }
}
