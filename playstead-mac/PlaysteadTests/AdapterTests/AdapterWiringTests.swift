import XCTest
import CryptoKit
@testable import Playstead

/// Proves the adapter install/verify/launch chain and the readiness gate
/// are reachable **from the assembled app**, not merely constructible in
/// isolation — the same discipline `ShellWiringTests` established.
///
/// `AdapterInstaller` used to be referenced only from `InstallerTests`,
/// `AdapterHost.setInstallState` had no production caller at all, and
/// `ReadinessEngine`/`ReadinessReportView` were instantiated only in
/// tests. Every one of those suites passed while the feature was
/// unreachable from the shipped app. These tests drive the real
/// `AppEnvironment` and only the code paths the shipped UI drives, so
/// removing the wiring fails them.
@MainActor
final class AdapterWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var environment: AppEnvironment!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        environment = AppEnvironment(
            paths: paths,
            apiClient: apiClient,
            reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
    }

    override func tearDownWithError() throws {
        environment = nil
        StubURLProtocol.reset()
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Raised when the stand-in binary could not be re-signed — see
    /// `installStandInExecutable` for why that is fatal to the fixture.
    struct StandInSigningFailure: Error { let status: Int32 }

    /// Places a real, runnable stand-in executable at
    /// `appURL/executableRelativePath` — no emulator is available in this
    /// environment, so `/bin/echo` stands in for one, exactly as
    /// `PlaySessionTests` already does.
    ///
    /// **Why the copy is re-signed.** macOS routes a spawn of a file it
    /// recognises as an *application bundle's main executable* through a
    /// security assessment before it lets the child run. It applies that
    /// recognition when the bundle carries a `Contents/Info.plist`, and —
    /// absent one — when the executable's own name matches the enclosing
    /// `.app`'s. `/bin/echo`'s signature is only valid at its platform
    /// path, so a plain copy fails that assessment, and the failure mode
    /// is silent: `Process.run()` succeeds, the child is left suspended
    /// at `_dyld_start` forever, and `terminationHandler` therefore never
    /// fires. Ad-hoc re-signing the copy makes it valid where it now
    /// lives, which is exactly the property the real pinned adapter (a
    /// signed, notarised `mGBA.app`) already has.
    ///
    /// Signing here rather than at each call site is deliberate: without
    /// it a fixture is launchable only by the accident of what its
    /// executable happens to be named relative to its bundle.
    private nonisolated static func installStandInExecutable(
        in appURL: URL, at executableRelativePath: String
    ) throws {
        let executableURL = appURL.appendingPathComponent(executableRelativePath)
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executableURL.path
        )

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", executableURL.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        // A stand-in that cannot be re-signed would launch and then hang
        // forever rather than fail, so this refuses loudly and up front.
        guard codesign.terminationStatus == 0 else {
            throw StandInSigningFailure(status: codesign.terminationStatus)
        }
    }

    /// A stand-in application bundle laid out exactly as the pin
    /// describes, whose program file is a real, runnable executable.
    private func makeRunnableAdapterBundle() throws -> URL {
        let pin = try AdapterPin.load()
        let appURL = tempRoot.appendingPathComponent("Stand-In.app", isDirectory: true)
        try Self.installStandInExecutable(in: appURL, at: pin.launch.executableRelativePath)
        return appURL
    }

    @discardableResult
    private func seedVerifiedObject(seed: String, bytes: Int = 256) throws -> (sha256: String, size: Int) {
        let seedByte = Int(seed.utf8.first ?? 0)
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((i + seedByte) & 0xFF) }
        let data = Data(raw)
        let digest = sha256Hex(data)
        let partial = try paths.partialURL(for: digest)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try data.write(to: partial)
        try environment.casManager.commit(partialAt: partial, sha256: digest)
        return (digest, bytes)
    }

    private func seedPlayableEntry(id: String = "asset-1") throws -> CatalogueEntry {
        let member = try seedVerifiedObject(seed: id)
        let entry = CatalogueEntry(
            id: id, system: "gba", displayTitle: "Stand-In Title", tags: [:],
            members: [AssetMember(
                ordinal: 0, role: "rom", required: true,
                sha256: member.sha256, size: member.size, name: "rom.gba"
            )]
        )
        try environment.catalogueStore.upsert(entry)
        return entry
    }

    // MARK: - Install → verify → launch, through the assembled app

    /// The whole point of the digest split: an installation registered
    /// through the shipped app's own entry point must actually launch.
    /// Before the fix, `verifyInstalledDigest()` compared the expanded
    /// executable's hash against the *archive* digest in `AdapterPin`, so
    /// this chain could never succeed and every launch threw
    /// `digestMismatch`.
    func testSelectingAnAdapterThroughTheEnvironmentMakesLaunchVerificationSucceedAndActuallyLaunch() async throws {
        let appURL = try makeRunnableAdapterBundle()

        XCTAssertEqual(environment.adapterInstallState, .notInstalled)
        let selected = await environment.selectExistingAdapter(appURL: appURL)
        XCTAssertTrue(selected, "selecting an existing adapter through the app must succeed")

        guard case .installed(let path, let verified) = environment.adapterInstallState else {
            return XCTFail("expected the environment to hold an installed adapter state")
        }
        XCTAssertTrue(verified)
        XCTAssertEqual(environment.adapterProvenance, .userSelected)
        XCTAssertEqual(environment.adapterSetupPhase, .idle)

        guard let host = environment.adapterHost else { return XCTFail("expected an adapter host") }
        // The install state actually reached the host the shipped launch
        // path uses — not a separately constructed one.
        try await host.verifyInstalledDigest()

        let saveDir = tempRoot.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let exited = expectation(description: "the adapter process exits")
        _ = try await host.launch(romPath: "/tmp/rom.gba", saveDir: saveDir.path) { _ in
            exited.fulfill()
        }
        await fulfillment(of: [exited], timeout: Self.firstLaunchTimeout)

        XCTAssertEqual(path, appURL.appendingPathComponent(try AdapterPin.load().launch.executableRelativePath).path)
    }

    /// Re-verification must stay genuine (P2-CR-001): the fix changed
    /// which digest launch compares against, never whether it re-hashes.
    func testLaunchStillRefusesWhenTheInstalledExecutableIsChangedAfterInstall() async throws {
        let appURL = try makeRunnableAdapterBundle()
        _ = await environment.selectExistingAdapter(appURL: appURL)
        guard let host = environment.adapterHost else { return XCTFail("expected an adapter host") }
        try await host.verifyInstalledDigest()

        // Swap the bytes on disk after the installation was recorded.
        let executableURL = appURL.appendingPathComponent(try AdapterPin.load().launch.executableRelativePath)
        try Data("a different binary entirely".utf8).write(to: executableURL)

        do {
            try await host.verifyInstalledDigest()
            XCTFail("expected a digest mismatch after the installed executable changed")
        } catch let error as AdapterHost.LaunchError {
            guard case .digestMismatch(let expected, let actual) = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
            XCTAssertEqual(actual, sha256Hex(Data("a different binary entirely".utf8)))
            XCTAssertNotEqual(expected, actual)
        }
    }

    /// The download path's own end of the chain: `install()` verifies the
    /// **archive** against the pin, records the **executable**'s digest,
    /// and a real `AdapterHost` handed that installation verifies and
    /// launches. Uses a fixture pin because the real pin's archive digest
    /// describes a 100MB+ published release that cannot be synthesised
    /// here.
    func testInstallResultVerifiesAndLaunchesThroughARealAdapterHost() async throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.fixturePinJSON.utf8))
        let emulatorsRoot = tempRoot.appendingPathComponent("fixture-emulators", isDirectory: true)
        let archiveBytes = Data("archive123".utf8)
        XCTAssertEqual(sha256Hex(archiveBytes), pin.sha256, "fixture archive must hash to the pinned archive digest")

        let installer = AdapterInstaller(
            pin: pin, emulatorsRoot: emulatorsRoot, localStore: environment.localStore,
            downloadArchive: { _ in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try archiveBytes.write(to: url)
                return url
            },
            archiveExpander: { _, destinationDir in
                let appURL = destinationDir.appendingPathComponent("Stand-In.app", isDirectory: true)
                try AdapterWiringTests.installStandInExecutable(in: appURL, at: pin.launch.executableRelativePath)
                return appURL
            }
        )

        let installation = try await installer.install()
        XCTAssertEqual(installation.archiveSHA256, pin.sha256, "the pin's digest is checked against the archive")
        XCTAssertNotEqual(
            installation.executableSHA256, pin.sha256,
            "the expanded executable is a different byte stream from the archive — conflating them was the bug"
        )

        let host = AdapterHost(pin: pin, emulatorsRoot: emulatorsRoot)
        await host.setInstallation(installation)
        try await host.verifyInstalledDigest()

        let saveDir = tempRoot.appendingPathComponent("fixture-saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let exited = expectation(description: "the installed adapter process exits")
        _ = try await host.launch(romPath: "/tmp/rom.gba", saveDir: saveDir.path) { _ in exited.fulfill() }
        await fulfillment(of: [exited], timeout: Self.firstLaunchTimeout)
    }

    /// An installation recorded in a previous session must come back on
    /// a cold start — otherwise the app forgets an emulator that is
    /// sitting right there on disk.
    func testARecordedInstallationIsRestoredByAFreshlyAssembledEnvironment() async throws {
        let appURL = try makeRunnableAdapterBundle()
        _ = await environment.selectExistingAdapter(appURL: appURL)

        // Simulate a relaunch: a brand new composition root over the same
        // on-disk root, with the network refusing everything.
        let restarted = AppEnvironment(
            paths: AppPaths(root: tempRoot),
            apiClient: APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential),
            reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )

        guard case .installed(_, let verified) = restarted.adapterInstallState else {
            return XCTFail("expected the recorded installation to be restored on a cold start")
        }
        XCTAssertTrue(verified)
        XCTAssertEqual(restarted.adapterProvenance, .userSelected)
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty, "restoring an installation must involve no network")
    }

    // MARK: - Play is gated by the real readiness engine

    /// With every required file cached but no emulator installed, Play
    /// must surface a readiness blocker carrying a remedy — not appear
    /// available and then fail with a raw "Launch failed: …" string.
    func testPlayIsBlockedByTheEmulatorCheckWithAnInstallRemedyWhenNoAdapterIsInstalled() throws {
        let entry = try seedPlayableEntry()
        StubURLProtocol.responder = { _ in
            XCTFail("the readiness path must never make a network request")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let report = environment.readinessReport(for: entry)

        XCTAssertFalse(report.isReady)
        guard let emulator = report.checks.first(where: { $0.kind == .emulator }) else {
            return XCTFail("expected the six-check report to include the emulator check")
        }
        XCTAssertTrue(emulator.outcome.isBlocking)
        XCTAssertEqual(emulator.remedy?.action, .installAdapter)
        XCTAssertFalse(emulator.remedy?.title.isEmpty ?? true)

        // Every blocking check carries an actionable remedy — the whole
        // reason Play routes through the report instead of an error
        // string.
        for check in report.checks where check.outcome.isBlocking {
            XCTAssertNotNil(check.remedy, "\(check.kind) blocks with no remedy")
        }

        // And the shipped row shows the blocker rather than a Play button.
        XCTAssertEqual(GameRowView.status(for: report), .blocked(report))
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty)
    }

    /// The gate has to actually open once its blocker is resolved through
    /// the app's own install surface.
    func testInstallingTheAdapterThroughTheEnvironmentClearsTheReadinessBlocker() async throws {
        let entry = try seedPlayableEntry()
        XCTAssertFalse(environment.readinessReport(for: entry).isReady)

        _ = await environment.selectExistingAdapter(appURL: try makeRunnableAdapterBundle())

        let report = environment.readinessReport(for: entry)
        XCTAssertTrue(report.isReady, "with the adapter installed and every file cached, Play must be available")
        XCTAssertEqual(GameRowView.status(for: report), .ready)
        // GBA declares no BIOS requirement, so an absent BIOS is ready,
        // never a blocker.
        XCTAssertEqual(report.checks.first(where: { $0.kind == .bios })?.outcome, .ready)
    }

    /// A missing file stays the row's Download action rather than a
    /// readiness sheet — D-17's "expose the action that is actually
    /// available".
    func testMissingRequiredFilesKeepTheRowOnDownloadRatherThanTheReadinessSheet() throws {
        let entry = CatalogueEntry(
            id: "asset-missing", system: "gba", displayTitle: "Not Downloaded", tags: [:],
            members: [AssetMember(
                ordinal: 0, role: "rom", required: true,
                sha256: String(repeating: "a", count: 64), size: 100, name: "rom.gba"
            )]
        )
        try environment.catalogueStore.upsert(entry)

        let report = environment.readinessReport(for: entry)
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(GameRowView.status(for: report), .needsDownload)
    }

    // MARK: - Honest install state on the surface the user sees

    func testTheAdapterSurfaceStatesEachInstallStateHonestly() async throws {
        XCTAssertTrue(
            AdapterSetupView.statusText(phase: .idle, installState: .notInstalled)
                .lowercased().contains("not installed")
        )
        XCTAssertTrue(
            AdapterSetupView.statusText(phase: .installing, installState: .notInstalled)
                .lowercased().contains("installing")
        )
        // A failure states its real reason, never a bare "failed".
        let reason = AppEnvironment.describeInstallFailure(
            AdapterInstallError.digestMismatch(expected: "aaa", actual: "bbb")
        )
        XCTAssertTrue(reason.contains("aaa") && reason.contains("bbb"))
        XCTAssertEqual(AdapterSetupView.statusText(phase: .failed(reason), installState: .notInstalled), reason)

        // A real failure through the environment lands in that phase.
        let notAnApp = tempRoot.appendingPathComponent("Empty.app", isDirectory: true)
        try FileManager.default.createDirectory(at: notAnApp, withIntermediateDirectories: true)
        let succeeded = await environment.selectExistingAdapter(appURL: notAnApp)
        XCTAssertFalse(succeeded)
        guard case .failed(let phaseReason) = environment.adapterSetupPhase else {
            return XCTFail("expected a failed setup phase with a real reason")
        }
        XCTAssertFalse(phaseReason.isEmpty)
        XCTAssertEqual(environment.adapterInstallState, .notInstalled)
    }

    /// The capability card the surface renders comes from the real
    /// environment, and states plainly that a user-selected build was
    /// never checked against the pinned release.
    func testCapabilityCardFromTheEnvironmentDoesNotRestatePinnedSupportForAUserSelectedBuild() async throws {
        _ = await environment.selectExistingAdapter(appURL: try makeRunnableAdapterBundle())
        guard let card = environment.adapterCapabilityCard else { return XCTFail("expected a capability card") }

        XCTAssertTrue(card.installationLabelText.lowercased().contains("unverified"))
        XCTAssertFalse(card.installationLabelText.lowercased().contains("matches the pinned release"))
        XCTAssertTrue(card.renderedText.contains(try AdapterPin.load().sha256))
    }

    // MARK: - Server-supplied ids never splice into a save path unchecked

    func testSaveDirectoryRefusesAnAssetSetIdThatIsNotASafeFilename() {
        XCTAssertThrowsError(try environment.saveDirectoryURL(forAssetSetID: "../../etc/evil")) { error in
            XCTAssertEqual(error as? PathSafetyError, .unsafeFilename("../../etc/evil"))
        }
        XCTAssertNoThrow(try environment.saveDirectoryURL(forAssetSetID: "asset-1"))
    }

    // MARK: - Fixtures

    /// A launch of a correctly signed stand-in completes in ~0.2s, so
    /// this is headroom for a loaded machine, not a tolerance for a slow
    /// launch.
    ///
    /// It was previously 60s to absorb a supposed one-off "security
    /// assessment cost". That cost was not a cost at all: an unsigned
    /// stand-in is never released by macOS, so the wait was unbounded and
    /// the ceiling only decided how long the suite hung before failing.
    /// `installStandInExecutable` removes the cause, so the ceiling can
    /// be tight enough to fail fast if it ever returns.
    private static let firstLaunchTimeout: TimeInterval = 15

    private static let fixturePinJSON = """
    {
      "system": "gba",
      "emulator": "fixture",
      "version": "0.0.1",
      "download_url": "https://example.invalid/archive.dmg",
      "sha256": "a435f6806bfd6c55ab979fd306a74ee2edf49308e7137a1527931249c43d31e0",
      "launch": {
        "executable_relative_path": "Contents/MacOS/Stand-In",
        "argument_template": ["{romPath}"]
      },
      "config_injection": {
        "mechanism": "cli_config_override",
        "keys": {"save_directory": "-C savegamePath={path}", "bios_path": "-b {path}"}
      },
      "save_contract": {
        "artifact_glob": "{saveDir}/{romBaseName}.sav",
        "directory_key": "savegamePath",
        "flush_triggers": ["periodic_during_play_observed_every_24s"],
        "on_demand_flush_supported": false,
        "worst_case_loss_seconds": 24
      },
      "exit_detection": {
        "clean": {"terminationStatus": 0, "terminationReason": "exit"},
        "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"},
        "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}
      }
    }
    """
}
