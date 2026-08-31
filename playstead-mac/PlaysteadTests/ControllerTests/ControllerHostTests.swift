import XCTest
@testable import Playstead

/// A fully injectable `ControllerInputSource` — lets every test drive
/// connect/disconnect deterministically with no physical hardware,
/// exactly the gap the plan 03-01 spike left unproven (probe 5).
final class FakeControllerInputSource: ControllerInputSource {
    var currentControllers: [ControllerDescriptor] = []
    private var onConnect: ((ControllerDescriptor) -> Void)?
    private var onDisconnect: ((ControllerDescriptor) -> Void)?

    func startObserving(
        onConnect: @escaping (ControllerDescriptor) -> Void,
        onDisconnect: @escaping (ControllerDescriptor) -> Void
    ) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    func simulateConnect(_ descriptor: ControllerDescriptor) {
        currentControllers.append(descriptor)
        onConnect?(descriptor)
    }

    func simulateDisconnect(_ descriptor: ControllerDescriptor) {
        currentControllers.removeAll { $0.id == descriptor.id }
        onDisconnect?(descriptor)
    }
}

@MainActor
final class ControllerHostTests: XCTestCase {
    private static let controllerA = ControllerDescriptor(
        id: "ctrl-a", name: "Test Pad A", availableInputs: ControllerDescriptor.defaultInputs
    )
    private static let controllerB = ControllerDescriptor(
        id: "ctrl-b", name: "Test Pad B", availableInputs: ControllerDescriptor.defaultInputs
    )

    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Behavior: connecting publishes a descriptor with name + inputs

    func testConnectingPublishesDescriptorWithNameAndAvailableInputs() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)

        source.simulateConnect(Self.controllerA)

        guard case .connected(let descriptor) = host.connectionState else {
            return XCTFail("expected a connected state after connecting the first controller")
        }
        XCTAssertEqual(descriptor.name, "Test Pad A")
        XCTAssertEqual(descriptor.availableInputs, ControllerDescriptor.defaultInputs)
    }

    // MARK: - Behavior: the test view reflects each button/axis as pressed or moved

    func testEachButtonAndAxisReportedAsPressedAppearsInLiveInputs() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)
        source.simulateConnect(Self.controllerA)

        host.reportInput("buttonA", active: true)
        XCTAssertTrue(host.liveInputs.contains("buttonA"))

        host.reportInput("buttonA", active: false)
        XCTAssertFalse(host.liveInputs.contains("buttonA"))

        host.reportInput("dpadUp", active: true)
        XCTAssertTrue(host.liveInputs.contains("dpadUp"))
    }

    // MARK: - Behavior: a mapping assigns each adapter input and persists across a restart

    func testMappingAssignsEachAdapterInputAndSurvivesClosingAndReopeningTheStore() throws {
        let storeA = (try? LocalStore(paths: paths))!
        let mappingStoreA = ControllerMappingStore(localStore: storeA)

        var mapping = mappingStoreA.mapping(forControllerProductID: Self.controllerA.id)
        mapping = mapping.remapping(adapterInput: "A", to: "buttonB")
        mapping = mapping.remapping(adapterInput: "B", to: "buttonA")
        try mappingStoreA.save(mapping)

        // Simulate an application restart: close by dropping this
        // LocalStore/connection, then reopen a fresh one against the
        // same on-disk path.
        let storeB = try LocalStore(paths: paths)
        let mappingStoreB = ControllerMappingStore(localStore: storeB)
        let reloaded = mappingStoreB.mapping(forControllerProductID: Self.controllerA.id)

        XCTAssertEqual(reloaded.controllerInput(for: "A"), "buttonB")
        XCTAssertEqual(reloaded.controllerInput(for: "B"), "buttonA")
    }

    // MARK: - Behavior: reset restores the default mapping and persists that too

    func testResetRestoresDefaultMappingAndPersistsIt() throws {
        let store = try LocalStore(paths: paths)
        let mappingStore = ControllerMappingStore(localStore: store)

        var mapping = mappingStore.mapping(forControllerProductID: Self.controllerA.id)
        mapping = mapping.remapping(adapterInput: "A", to: "buttonY")
        try mappingStore.save(mapping)
        XCTAssertEqual(mappingStore.mapping(forControllerProductID: Self.controllerA.id).controllerInput(for: "A"), "buttonY")

        let reset = try mappingStore.reset(controllerProductID: Self.controllerA.id)
        XCTAssertEqual(reset, ControllerMapping.defaultMapping(controllerProductID: Self.controllerA.id))

        // Persisted, not just returned in-memory: a fresh store reload
        // still sees the default.
        let reopened = try LocalStore(paths: paths)
        let reloaded = ControllerMappingStore(localStore: reopened).mapping(forControllerProductID: Self.controllerA.id)
        XCTAssertEqual(reloaded, ControllerMapping.defaultMapping(controllerProductID: Self.controllerA.id))
    }

    // MARK: - Behavior: disconnecting publishes disconnected state and a non-modal recovery affordance

    func testDisconnectingPublishesDisconnectedStateAndShowsRecoveryAffordance() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)
        source.simulateConnect(Self.controllerA)
        XCTAssertNotEqual(host.connectionState, .disconnected)

        source.simulateDisconnect(Self.controllerA)

        XCTAssertEqual(host.connectionState, .disconnected)
        XCTAssertTrue(host.showRecoveryBanner)
        XCTAssertEqual(host.lastDisconnectedControllerName, "Test Pad A")
    }

    /// The recovery affordance is non-modal: every other operation this
    /// host exposes remains fully usable while `showRecoveryBanner` is
    /// true — nothing in `ControllerHost` gates on it.
    func testRecoveryAffordanceIsNonModalOtherControlsRemainEnabled() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)
        source.simulateConnect(Self.controllerA)
        source.simulateDisconnect(Self.controllerA)
        XCTAssertTrue(host.showRecoveryBanner)

        // A second controller can still be connected and assigned while
        // the banner is up — no operation is blocked by it.
        source.simulateConnect(Self.controllerB)
        host.assign(controllerID: Self.controllerB.id)
        XCTAssertEqual(host.connectionState, .connected(Self.controllerB))
        XCTAssertTrue(host.inputPathAvailability.keyboardAvailable)
        XCTAssertTrue(host.inputPathAvailability.pointerAvailable)
    }

    // MARK: - Behavior: while disconnected, keyboard and pointer remain able to operate every surface

    func testKeyboardAndPointerRemainAvailableWithControllerDisconnected() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)

        // No controller has ever connected.
        XCTAssertTrue(host.inputPathAvailability.keyboardAvailable)
        XCTAssertTrue(host.inputPathAvailability.pointerAvailable)
        XCTAssertFalse(host.inputPathAvailability.controllerAvailable)

        source.simulateConnect(Self.controllerA)
        source.simulateDisconnect(Self.controllerA)
        XCTAssertTrue(host.inputPathAvailability.keyboardAvailable)
        XCTAssertTrue(host.inputPathAvailability.pointerAvailable)
        XCTAssertFalse(host.inputPathAvailability.controllerAvailable)
    }

    // MARK: - Behavior: reconnecting restores controller input with no relaunch and dismisses recovery

    func testReconnectingRestoresControllerInputAndDismissesRecoveryAffordance() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)
        source.simulateConnect(Self.controllerA)
        source.simulateDisconnect(Self.controllerA)
        XCTAssertTrue(host.showRecoveryBanner)
        XCTAssertEqual(host.connectionState, .disconnected)

        source.simulateConnect(Self.controllerA)

        XCTAssertEqual(host.connectionState, .connected(Self.controllerA))
        XCTAssertFalse(host.showRecoveryBanner)
    }

    // MARK: - Behavior: with no controller ever connected, the input readiness check passes on keyboard availability

    func testInputReadinessCheckPassesWithZeroControllersConnected() throws {
        let cas = CASManager(paths: paths)
        let localStore = try LocalStore(paths: paths)
        let downloadQueue = DownloadQueue(localStore: localStore)
        let saveDir = tempRoot.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let engine = ReadinessEngine(
            cas: cas,
            downloadQueue: downloadQueue,
            adapterInstallState: { .installed(executablePath: "/usr/bin/true", verified: true) },
            biosRequired: false,
            hasManagedBIOS: { true },
            hasController: { false },
            hasKeyboard: { true },
            saveDirectoryURL: saveDir
        )

        let report = engine.evaluate(assetSetID: "game-1", requiredMembers: [])
        let controllerCheck = report.checks.first { $0.kind == .controllerAndInput }
        XCTAssertEqual(controllerCheck?.outcome, .ready)
        XCTAssertTrue(report.isReady)
    }

    // MARK: - Behavior: two controllers connected resolve to one assigned controller, reassignment changes it

    func testTwoConnectedControllersResolveToOneAssignedControllerAndReassignmentChangesIt() {
        let source = FakeControllerInputSource()
        let host = ControllerHost(source: source)

        source.simulateConnect(Self.controllerA)
        source.simulateConnect(Self.controllerB)

        XCTAssertEqual(host.connectedControllers.count, 2)
        XCTAssertEqual(host.connectionState, .connected(Self.controllerA))

        host.assign(controllerID: Self.controllerB.id)
        XCTAssertEqual(host.connectionState, .connected(Self.controllerB))
    }

    // MARK: - Acceptance: the configuration injected into the adapter at launch contains the mapped values

    func testAdapterHostInjectsMappedControllerValuesIntoLaunchArguments() async throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.pinJSON.utf8))
        let host = AdapterHost(pin: pin, emulatorsRoot: paths.emulators)

        var mapping = ControllerMapping.defaultMapping(controllerProductID: Self.controllerA.id)
        mapping = mapping.remapping(adapterInput: "A", to: "buttonB")
        await host.setControllerMapping(mapping)

        let args = await host.renderedLaunchArguments(romPath: "/tmp/game.gba", saveDir: "/tmp/saves")

        XCTAssertTrue(args.contains("input.A=buttonB"), "expected the remapped A input in the injected configuration, got \(args)")
        // Every other input's default mapping is also present.
        XCTAssertTrue(args.contains("input.Up=dpadUp"))
    }

    func testAdapterHostLaunchArgumentsUnchangedWithNoActiveMapping() async throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.pinJSON.utf8))
        let host = AdapterHost(pin: pin, emulatorsRoot: paths.emulators)

        let args = await host.renderedLaunchArguments(romPath: "/tmp/game.gba", saveDir: "/tmp/saves")

        XCTAssertEqual(args, ["-C", "savegamePath=/tmp/saves", "/tmp/game.gba"])
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
}
