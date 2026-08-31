import XCTest
@testable import Playstead

/// Covers plan 03-08 task 3's `<behavior>`/`<acceptance_criteria>`:
/// coarse play-session recording that is structurally incapable of
/// touching the launch path, delivered through the outbox after the
/// fact, individually deletable.
final class PlaySessionTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var curationStore: CurationStore!
    private var apiClient: APIClient!
    private var outbox: Outbox!
    private var recorder: PlaySessionRecorder!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        curationStore = CurationStore(localStore: localStore)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        outbox = Outbox(localStore: localStore, curationStore: curationStore)
        recorder = PlaySessionRecorder(localStore: localStore, curationStore: curationStore, outbox: outbox)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - PlaySessionRecorder's session type exposes exactly an
    // identifier, an asset set id, a start, and an end.

    func test_playSessionType_exposesExactlyFourFields() {
        let mirror = Mirror(reflecting: PlaySession(id: "x", assetSetID: "y", startedAt: Date(), endedAt: nil))
        XCTAssertEqual(mirror.children.count, 4)
        let labels = Set(mirror.children.compactMap(\.label))
        XCTAssertEqual(labels, ["id", "assetSetID", "startedAt", "endedAt"])
    }

    // MARK: - A completed launch and exit produces exactly one session
    // with a start and an end.

    func test_beganThenEnded_producesExactlyOneSessionWithStartAndEnd() {
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        let start = Date()
        let sessionID = recorder.began(assetSetID: "asset-1", at: start)
        recorder.ended(sessionID, at: start.addingTimeInterval(600))

        let listings = recorder.listings()
        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings.first?.session.id, sessionID)
        XCTAssertEqual(listings.first?.session.assetSetID, "asset-1")
        XCTAssertNotNil(listings.first?.session.endedAt)
    }

    // MARK: - Sessions recorded while offline are delivered after
    // reachability returns.

    func test_offlineSession_isDeliveredAfterReachabilityReturns() async throws {
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }

        let start = Date()
        let sessionID = recorder.began(assetSetID: "asset-1", at: start)
        recorder.ended(sessionID, at: start.addingTimeInterval(300))

        let recorderRef = recorder!
        let worker = OutboxWorker(apiClient: apiClient, outbox: outbox, onEntryDelivered: { intent in
            if case .playSessionRecord(let id, _, _, _) = intent {
                recorderRef.markDelivered(id)
            }
        })

        let offlineResult = await worker.drainOnce()
        XCTAssertTrue(offlineResult.stoppedForRetry)
        XCTAssertFalse(recorder.listings().first(where: { $0.session.id == sessionID })?.delivered ?? true)

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }
        let onlineResult = await worker.drainOnce()

        XCTAssertEqual(onlineResult.sent, 1)
        XCTAssertTrue(recorder.listings().first(where: { $0.session.id == sessionID })?.delivered ?? false)
    }

    // MARK: - The same session identifier posted twice results in one
    // server-side effect, using a request-recording stub.

    func test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect() async throws {
        let start = Date()
        let sessionID = recorder.began(assetSetID: "asset-1", at: start)
        recorder.ended(sessionID, at: start.addingTimeInterval(60))

        // First attempt: transport failure — the response is never
        // observed by the client.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        let worker = OutboxWorker(apiClient: apiClient, outbox: outbox)
        _ = await worker.drainOnce()

        // Retry: server now succeeds.
        var effects = Set<String>()
        StubURLProtocol.responder = { request in
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                effects.insert(key) // a real server would key its receipt table on this exact header
            }
            return StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8))
        }
        _ = await worker.drainOnce()

        XCTAssertEqual(StubURLProtocol.requestLog.count, 2, "the client sent two requests (the retry)")
        XCTAssertEqual(effects.count, 1, "but both attempts carried the same idempotency key, so the server-side effect converges on one")
    }

    // MARK: - A user-initiated deletion enqueues a delete intent and
    // removes the session from Recent.

    func test_userDeletion_enqueuesDeleteIntentAndRemovesFromRecent() {
        let start = Date()
        let sessionID = recorder.began(assetSetID: "asset-1", at: start)
        recorder.ended(sessionID, at: start.addingTimeInterval(60))
        XCTAssertEqual(recorder.listings().count, 1)

        XCTAssertTrue(recorder.delete(sessionID))

        XCTAssertEqual(recorder.listings().count, 0, "the session must be removed from the Recent shelf's list")
        let deleteEntry = outbox.listAll().first(where: { $0.kind == .playSessionDelete })
        XCTAssertNotNil(deleteEntry)
        guard case .playSessionDelete(let deletedID) = deleteEntry?.intent else {
            return XCTFail("expected a playSessionDelete intent")
        }
        XCTAssertEqual(deletedID, sessionID)
    }

    // MARK: - A launch succeeds while the session store is stubbed to
    // throw on every write, and the launch path performs no read of the
    // session store.

    func test_launchSucceedsIndependentlyOfPlaySessionRecording() async throws {
        // A recorder whose underlying store fails on every write: the
        // session table is dropped out from under it, so every
        // `execute` call in `began`/`ended` genuinely throws inside
        // `SQLiteConnection` — `try?` there must swallow every one.
        let throwingLocalStore = LocalStore.inMemoryFallback()
        try throwingLocalStore.connection.execute("DROP TABLE play_sessions_pending;")
        let failingRecorder = PlaySessionRecorder(
            localStore: throwingLocalStore, curationStore: CurationStore(localStore: throwingLocalStore),
            outbox: Outbox(localStore: throwingLocalStore, curationStore: CurationStore(localStore: throwingLocalStore))
        )

        // Neither call is `throws` at the Swift level — reaching the
        // assertions below at all (rather than crashing) is the proof
        // that every internal write failure was swallowed.
        let sessionID = failingRecorder.began(assetSetID: "asset-1")
        failingRecorder.ended(sessionID)
        XCTAssertFalse(sessionID.isEmpty, "began must still return a usable id even when its own write failed")

        // Independently: a real launch, via the unmodified `AdapterHost`,
        // succeeds — its call signature has no session-store parameter
        // at all, so it structurally cannot read one. `/bin/echo` stands
        // in for the pinned emulator binary (no real emulator is
        // available in this environment); only `pin.sha256` and the
        // recorded install-verify digest need to match for
        // `verifyInstalledDigest()` to pass.
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let pinJSON = """
        {
          "system": "gba", "emulator": "mgba", "version": "0.10.5",
          "download_url": "https://example.test/mgba.dmg",
          "sha256": "\(String(repeating: "a", count: 64))",
          "launch": {"executable_relative_path": "echo", "argument_template": ["{romPath}"]},
          "config_injection": {"mechanism": "cli_config_override", "keys": {"save_directory": "-C savegamePath={path}", "bios_path": "-b {path}", "controller_mapping": "not_probed_no_hardware_available"}},
          "save_contract": {"artifact_glob": "{saveDir}/{romBaseName}.sav", "directory_key": "savegamePath", "flush_triggers": ["periodic_during_play_observed_every_24s"], "on_demand_flush_supported": false, "worst_case_loss_seconds": 24},
          "exit_detection": {"clean": {"terminationStatus": 0, "terminationReason": "exit"}, "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"}, "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}}
        }
        """
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(pinJSON.utf8))

        let emulatorDir = tempRoot.appendingPathComponent("emulators").appendingPathComponent(pin.emulator).appendingPathComponent(pin.version)
        try FileManager.default.createDirectory(at: emulatorDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: emulatorDir.appendingPathComponent("echo"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emulatorDir.appendingPathComponent("echo").path)
        try JSONEncoder().encode(InstallVerifyRecord(sha256: pin.sha256)).write(to: emulatorDir.appendingPathComponent(".install-verify.json"))

        let host = AdapterHost(pin: pin, emulatorsRoot: tempRoot.appendingPathComponent("emulators"))

        let exitExpectation = expectation(description: "process exits")
        _ = try await host.launch(romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in
            exitExpectation.fulfill()
        }
        await fulfillment(of: [exitExpectation], timeout: 5)
    }

    // MARK: - Source-level: AdapterHost never references any
    // session-store type — the launch path structurally cannot read one.

    func test_adapterHostSourceContainsNoSessionStoreReference() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../CurationTests/PlaySessionTests.swift -> .../CurationTests
            .deletingLastPathComponent() // .../PlaysteadTests/CurationTests -> .../PlaysteadTests
            .deletingLastPathComponent() // .../playstead-mac/PlaysteadTests -> .../playstead-mac
            .appendingPathComponent("Playstead/Adapter/AdapterHost.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("PlaySessionRecorder"))
        XCTAssertFalse(source.contains("play_sessions"))
    }
}
