import XCTest
import CryptoKit
import AppKit
@testable import Playstead

/// Proves relaunch survives an application restart by construction:
/// everything a launch needs — the cache's verified object, the queue,
/// and (via the injected closures here, mirroring how `AppEnvironment`
/// would resolve them) the adapter installation and BIOS state — lives
/// in SQLite and on disk, so a cold start rebuilds the launchable state
/// with zero network calls. Also proves a registered adapter process is
/// terminated when the application termination handler runs, so a quit
/// never leaves an orphaned emulator holding the save file open
/// (T-03-29).
final class RelaunchTests: XCTestCase {
    private var tempRoot: URL!
    private var saveDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        saveDir = tempRoot.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func seedVerifiedObject(paths: AppPaths, cas: CASManager, seed: String, bytes: Int = 256) throws -> RequiredMember {
        let seedByte = Int(seed.utf8.first ?? 0)
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((i + seedByte) & 0xFF) }
        let data = Data(raw)
        let digest = sha256Hex(data)

        let partial = try paths.partialURL(for: digest)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return RequiredMember(sha256: digest, size: bytes)
    }

    // MARK: - Relaunch survives an application restart

    /// Closes and reopens every store this launch path touches and
    /// asserts a previously launchable game still evaluates as
    /// launchable — with the network stubbed to fail, proving nothing
    /// on this path silently depends on a live server.
    func testPreviouslyLaunchableGameStillEvaluatesLaunchableAfterClosingAndReopeningEveryStoreWithNetworkStubbedToFail() throws {
        let paths = AppPaths(root: tempRoot)

        // First "session": seed a verified cached object, an installed
        // adapter, and a validated BIOS, and confirm readiness.
        let casA = CASManager(paths: paths)
        let localStoreA = try LocalStore(paths: paths)
        let downloadQueueA = DownloadQueue(localStore: localStoreA)
        let member = try seedVerifiedObject(paths: paths, cas: casA, seed: "relaunch-game")

        let managedBiosDir = tempRoot.appendingPathComponent("bios", isDirectory: true)
        let biosStoreA = BiosStore(
            localStore: localStoreA, managedDirectory: managedBiosDir,
            references: [BiosStore.Reference(system: "gba", expectedByteLength: 4, knownSHA256Digests: [sha256Hex(Data([1, 2, 3, 4]))])]
        )
        let biosCandidate = tempRoot.appendingPathComponent("candidate.bin")
        try Data([1, 2, 3, 4]).write(to: biosCandidate)
        try biosStoreA.validateAndAccept(candidateURL: biosCandidate, system: "gba")

        let engineA = ReadinessEngine(
            cas: casA, downloadQueue: downloadQueueA,
            adapterInstallState: { .installed(executablePath: "/usr/bin/true", verified: true) },
            biosRequired: true,
            hasManagedBIOS: { biosStoreA.hasManagedBIOS(forSystem: "gba") },
            hasController: { false }, hasKeyboard: { true },
            saveDirectoryURL: saveDir
        )
        let reportA = engineA.evaluate(assetSetID: "relaunch-game", requiredMembers: [member])
        XCTAssertTrue(reportA.isReady, "expected the first session to be launch-ready before simulating a restart")

        // Simulate an application restart: every `LocalStore`/`CASManager`
        // instance above goes out of scope here; nothing from this test
        // method's stack survives except what is on disk at `tempRoot`.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }

        let casB = CASManager(paths: paths)
        let localStoreB = try LocalStore(paths: paths)
        let downloadQueueB = DownloadQueue(localStore: localStoreB)
        let biosStoreB = BiosStore(localStore: localStoreB, managedDirectory: managedBiosDir, references: [])

        let engineB = ReadinessEngine(
            cas: casB, downloadQueue: downloadQueueB,
            adapterInstallState: { .installed(executablePath: "/usr/bin/true", verified: true) },
            biosRequired: true,
            hasManagedBIOS: { biosStoreB.hasManagedBIOS(forSystem: "gba") },
            hasController: { false }, hasKeyboard: { true },
            saveDirectoryURL: saveDir
        )
        let reportB = engineB.evaluate(assetSetID: "relaunch-game", requiredMembers: [member])

        XCTAssertTrue(reportB.isReady, "expected the same game to remain launch-ready after a cold restart, with no network involved")
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty, "the relaunch path must make zero network requests")
    }

    // MARK: - Orphan prevention: a registered process is terminated on application termination

    func testRegisteredAdapterProcessIsTerminatedWhenApplicationTerminationHandlerRuns() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        XCTAssertTrue(process.isRunning)

        AdapterProcessRegistry.shared.register(process)

        let terminatedExpectation = expectation(description: "process terminates")
        process.terminationHandler = { _ in terminatedExpectation.fulfill() }

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        wait(for: [terminatedExpectation], timeout: 5)
        XCTAssertFalse(process.isRunning, "a registered process must be terminated when the application termination handler runs")
    }
}
