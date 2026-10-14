import XCTest
import CryptoKit
@testable import Playstead

final class MGBAInputBridgeTests: XCTestCase {
    private let device = SDLDeviceSnapshot(
        instanceID: 41, guid: "private-test-guid", name: "Synthetic SDL Device",
        bindings: [
            "dpadUp": .button(11), "dpadDown": .button(12), "dpadLeft": .button(13), "dpadRight": .button(14),
            "buttonA": .button(0), "buttonB": .button(1), "leftShoulder": .button(9), "rightShoulder": .button(10),
            "buttonStart": .button(6), "buttonBack": .button(4),
            "leftX": .axis(index: 0, sign: 1), "leftY": .axis(index: 1, sign: 1)
        ]
    )
    private let generation: UInt64 = 7

    private func validEdges() -> ([AssignedInputEdge], [SDLInputEdge]) {
        let events: [(String, Bool)] = [
            ("buttonA", true), ("buttonA", false), ("leftShoulder", true), ("leftShoulder", false)
        ]
        return (
            events.map { AssignedInputEdge(controllerID: "assigned-runtime-1", input: $0.0, pressed: $0.1) },
            events.map { SDLInputEdge(instanceID: 41, input: $0.0, pressed: $0.1, generation: generation) }
        )
    }

    private func mapping() -> ControllerMapping {
        ControllerMapping.defaultMapping(controllerProductID: "assigned-runtime-1")
    }

    private struct FiniteSDLSource: SDLDeviceEventSource {
        let generation: UInt64
        let values: [SDLDeviceSnapshot]
        let edges: [SDLInputEdge]
        var delayedIndex: Int? = nil
        var delay: Duration = .zero
        func devices() throws -> (generation: UInt64, devices: [SDLDeviceSnapshot]) { (generation, values) }
        func inputEdges() -> AsyncThrowingStream<SDLInputEdge, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    for (index, edge) in edges.enumerated() {
                        if index == delayedIndex { try? await ContinuousClock().sleep(for: delay) }
                        continuation.yield(edge)
                    }
                    continuation.finish()
                }
            }
        }
    }

    @MainActor
    private final class FiniteAssignedSource: AssignedControllerEventSource {
        let assignedControllerID: String?
        let edges: [AssignedInputEdge]
        init(id: String?, edges: [AssignedInputEdge]) { assignedControllerID = id; self.edges = edges }
        func inputEdges() -> AsyncStream<AssignedInputEdge> {
            AsyncStream { continuation in
                for edge in edges { continuation.yield(edge) }
                continuation.finish()
            }
        }
    }

    func testAttestsUniqueAssignedDeviceAndDeliversItsBindingToChild() async throws {
        let (gc, sdl) = validEdges()
        let (proof, selectedDevice) = try await MGBAInputBridge.attest(
            assignedSource: FiniteAssignedSource(id: "assigned-runtime-1", edges: gc),
            sdlSource: FiniteSDLSource(generation: generation, values: [device], edges: sdl)
        )
        let text = try MGBAInputBridge.config(mapping: mapping(), attestation: proof, currentControllerID: "assigned-runtime-1", generation: generation, device: selectedDevice)
        XCTAssertTrue(text.contains("[gba.input.SDLB]"))
        XCTAssertTrue(text.contains("keyA=0"))
        XCTAssertTrue(text.contains("keyB=1"))
        XCTAssertTrue(text.contains("keyUp=11"))
        XCTAssertTrue(text.contains("keySelect=4"))
        XCTAssertTrue(text.contains("keyStart=6"))
        XCTAssertTrue(text.contains("axisLeftAxis=-0"))
        XCTAssertTrue(text.contains("axisRightAxis=+0"))
        XCTAssertTrue(text.contains("axisUpAxis=-1"))
        XCTAssertTrue(text.contains("axisDownAxis=+1"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capturedConfig = root.appendingPathComponent("child-config.ini")
        let capturedRoot = root.appendingPathComponent("child-config-root.txt")
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.childFixturePin.utf8))
        let shell = URL(fileURLWithPath: "/bin/sh")
        let shellBytes = try Data(contentsOf: shell)
        let digest = SHA256.hash(data: shellBytes).map { String(format: "%02x", $0) }.joined()
        let installation = AdapterInstallation(
            emulator: pin.emulator, version: pin.version, executablePath: shell.path,
            archiveSHA256: nil, executableSHA256: digest, provenance: .userSelected, verified: true
        )
        let host = AdapterHost(pin: pin, emulatorsRoot: root, processRegistry: .isolatedForTesting())
        await host.setInstallation(installation)
        await host.setControllerMapping(mapping())
        await host.setControllerInputAttestation(proof, device: selectedDevice, generation: generation)
        let exited = expectation(description: "stand-in child consumed launch config")
        _ = try await host.launch(
            assetSetID: "mgba-input-bridge-\(UUID().uuidString)",
            romPath: capturedConfig.path, saveDir: capturedRoot.path
        ) { _ in exited.fulfill() }
        await fulfillment(of: [exited], timeout: 10)
        XCTAssertEqual(try String(contentsOf: capturedConfig, encoding: .utf8), text)
        let privateRootPath = try String(contentsOf: capturedRoot, encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateRootPath), "per-launch private config must be removed after child exit")
    }

    func testRejectsUnassignedOrMismatchedInputEdges() async throws {
        let (gc, sdl) = validEdges()
        let wrongGC = [AssignedInputEdge(controllerID: "another-controller", input: "buttonA", pressed: true)] + gc.dropFirst()
        do {
            _ = try await MGBAInputBridge.attest(assignedSource: FiniteAssignedSource(id: "assigned-runtime-1", edges: wrongGC), sdlSource: FiniteSDLSource(generation: generation, values: [device], edges: sdl))
            XCTFail("unassigned input must not establish identity")
        } catch { }
        let wrongSDL = [SDLInputEdge(instanceID: 99, input: "buttonA", pressed: true, generation: generation)] + sdl.dropFirst()
        do {
            _ = try await MGBAInputBridge.attest(assignedSource: FiniteAssignedSource(id: "assigned-runtime-1", edges: gc), sdlSource: FiniteSDLSource(generation: generation, values: [device], edges: wrongSDL))
            XCTFail("another SDL instance must not establish identity")
        } catch { }
        let reversed = Array(gc.reversed())
        XCTAssertThrowsError(try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: reversed, sdlEdges: sdl))
    }

    func testRejectsZeroMultipleOrCompetingSDLDevices() async throws {
        XCTAssertThrowsError(try MGBAInputBridge.requireUniqueDevice([]))
        XCTAssertThrowsError(try MGBAInputBridge.requireUniqueDevice([device, device]))
        let (gc, sdl) = validEdges()
        let competing = [SDLInputEdge(instanceID: 42, input: "buttonA", pressed: true, generation: generation)] + sdl
        do {
            _ = try await MGBAInputBridge.attest(assignedSource: FiniteAssignedSource(id: "assigned-runtime-1", edges: gc), sdlSource: FiniteSDLSource(generation: generation, values: [device], edges: competing))
            XCTFail("competing SDL input must not establish identity")
        } catch { }
    }

    func testChallengeRejectsEventsOutsideMonotonicCorrelationWindow() async throws {
        let (gc, sdl) = validEdges()
        let delayedSDL = FiniteSDLSource(
            generation: generation, values: [device], edges: sdl,
            delayedIndex: 2, delay: .seconds(1.1)
        )
        do {
            _ = try await MGBAInputBridge.attest(
                assignedSource: FiniteAssignedSource(id: "assigned-runtime-1", edges: gc),
                sdlSource: delayedSDL
            )
            XCTFail("edges received outside the monotonic correlation window must be rejected")
        } catch { }
    }

    func testInvalidatesAttestationOnGenerationOrAssignmentChange() throws {
        let (gc, sdl) = validEdges()
        let proof = try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: gc, sdlEdges: sdl)
        XCTAssertThrowsError(try MGBAInputBridge.config(mapping: mapping(), attestation: proof, currentControllerID: "other-controller", generation: generation, device: device))
        XCTAssertThrowsError(try MGBAInputBridge.config(mapping: mapping(), attestation: proof, currentControllerID: "assigned-runtime-1", generation: generation + 1, device: device))
    }

    func testMissingAndStaleAttestationsBlockStandInChildSpawn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("spawned")
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.childFixturePin.utf8))
        let shell = URL(fileURLWithPath: "/bin/sh")
        let digest = SHA256.hash(data: try Data(contentsOf: shell)).map { String(format: "%02x", $0) }.joined()
        let installation = AdapterInstallation(emulator: pin.emulator, version: pin.version, executablePath: shell.path, archiveSHA256: nil, executableSHA256: digest, provenance: .userSelected, verified: true)
        let host = AdapterHost(pin: pin, emulatorsRoot: root, processRegistry: .isolatedForTesting())
        await host.setInstallation(installation)
        await host.setControllerMapping(mapping())
        do {
            _ = try await host.launch(assetSetID: "missing-proof-\(UUID().uuidString)", romPath: marker.path, saveDir: marker.path) { _ in }
            XCTFail("launch without identity proof must fail closed")
        } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "missing attestation must reject before child spawn")

        let (gc, sdl) = validEdges()
        let proof = try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: gc, sdlEdges: sdl)
        let staleDevice = SDLDeviceSnapshot(instanceID: device.instanceID, guid: "different-private-guid", name: device.name, bindings: device.bindings)
        await host.setControllerInputAttestation(proof, device: device, generation: generation)
        do {
            _ = try await host.launch(
                assetSetID: "stale-proof-\(UUID().uuidString)", romPath: marker.path, saveDir: marker.path,
                currentInputIdentity: { (controllerID: "assigned-runtime-1", generation: self.generation, device: staleDevice) }
            ) { _ in }
            XCTFail("stale SDL identity must fail closed")
        } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "stale identity must reject before child spawn")
    }

    @MainActor
    func testLaunchCoordinatorResumesOnlyAfterSuccessfulChallengeAndHonorsCancel() async throws {
        var resumed = false
        try await ControllerChallengeLaunchCoordinator.perform(
            challenge: {},
            resumeLaunch: { resumed = true }
        )
        XCTAssertTrue(resumed)

        resumed = false
        do {
            try await ControllerChallengeLaunchCoordinator.perform(
                challenge: { throw BridgeError.staleAttestation },
                resumeLaunch: { resumed = true }
            )
            XCTFail("failed attestation must not resume launch")
        } catch { }
        XCTAssertFalse(resumed)

        var challenged = false
        let cancelled = Task { @MainActor in
            try await ControllerChallengeLaunchCoordinator.perform(
                challenge: { challenged = true },
                resumeLaunch: { resumed = true }
            )
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("cancelled launch request should throw")
        } catch is CancellationError { }
        XCTAssertFalse(challenged)
        XCTAssertFalse(resumed)
    }

    @MainActor
    func testAttestationIsReusedUntilAssignedControllerSessionInvalidates() async throws {
        let (gc, sdl) = validEdges()
        let proof = try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: gc, sdlEdges: sdl)
        let session = ControllerAttestationSession()
        var challengeCount = 0
        let first = try await session.attestation {
            challengeCount += 1
            return (proof, self.device)
        }
        let second = try await session.attestation {
            challengeCount += 1
            return (proof, self.device)
        }
        XCTAssertEqual(first.0, second.0)
        XCTAssertEqual(challengeCount, 1, "one successful challenge is reused for the assigned-controller session")
        session.invalidate()
        _ = try await session.attestation {
            challengeCount += 1
            return (proof, self.device)
        }
        XCTAssertEqual(challengeCount, 2, "assignment/disconnect invalidation requires a fresh challenge")
    }

    func testChangedRemapChangesNumericBindingAndDuplicateIsRejected() throws {
        let (gc, sdl) = validEdges()
        let proof = try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: gc, sdlEdges: sdl)
        let original = try MGBAInputBridge.config(mapping: mapping(), attestation: proof, currentControllerID: "assigned-runtime-1", generation: generation, device: device)
        let remapped = mapping().remapping(adapterInput: "A", to: "buttonB").remapping(adapterInput: "B", to: "buttonA")
        let changed = try MGBAInputBridge.config(mapping: remapped, attestation: proof, currentControllerID: "assigned-runtime-1", generation: generation, device: device)
        XCTAssertNotEqual(original, changed)
        XCTAssertTrue(changed.contains("keyA=1"))
        XCTAssertThrowsError(try MGBAInputBridge.config(mapping: mapping().remapping(adapterInput: "A", to: "buttonB"), attestation: proof, currentControllerID: "assigned-runtime-1", generation: generation, device: device))
    }

    func testPrivateConfigHasOwnerOnlyPermissionsAndIsLaunchScoped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configRoot = try MGBAInputBridge.writePrivateConfig("[gba.input.SDLB]\nkeyA=0\n", under: root)
        let attributes = try FileManager.default.attributesOfItem(atPath: configRoot.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let config = configRoot.appendingPathComponent("mgba/config.ini")
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "[gba.input.SDLB]\nkeyA=0\n")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testPrivateConfigIsRemovedWhenVerifiedChildCannotSpawn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("non-executable-stand-in")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sh"), to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
        let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.childFixturePin.utf8))
        let host = AdapterHost(pin: pin, emulatorsRoot: root, processRegistry: .isolatedForTesting(), privateConfigurationRoot: root.appendingPathComponent("configs"))
        await host.setInstallation(AdapterInstallation(emulator: pin.emulator, version: pin.version, executablePath: executable.path, archiveSHA256: nil, executableSHA256: digest, provenance: .userSelected, verified: true))
        await host.setControllerMapping(mapping())
        let (gc, sdl) = validEdges()
        let proof = try MGBAInputBridge.attest(controllerID: "assigned-runtime-1", device: device, generation: generation, gameControllerEdges: gc, sdlEdges: sdl)
        await host.setControllerInputAttestation(proof, device: device, generation: generation)
        do {
            _ = try await host.launch(assetSetID: "failed-spawn-\(UUID().uuidString)", romPath: "/tmp/rom.gba", saveDir: "/tmp/saves") { _ in }
            XCTFail("non-executable child should not spawn")
        } catch { }
        let configRoot = root.appendingPathComponent("configs")
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: configRoot.path)) ?? []
        XCTAssertTrue(remaining.isEmpty, "failed Process.run must clean the private XDG config")
    }

    private static let childFixturePin = """
    {
      "system":"gba","emulator":"fixture","version":"0.0.1",
      "download_url":"https://example.invalid/archive.dmg","sha256":"a435f6806bfd6c55ab979fd306a74ee2edf49308e7137a1527931249c43d31e0",
      "launch":{"executable_relative_path":"Contents/MacOS/Stand-In","argument_template":["-c","printf '%s' \\\"$XDG_CONFIG_HOME\\\" > \\\"$2\\\"; cat \\\"$XDG_CONFIG_HOME/mgba/config.ini\\\" > \\\"$1\\\"; sleep 0.1","stand-in","{romPath}","{saveDir}"]},
      "config_injection":{"mechanism":"cli_config_override","keys":{"save_directory":"-C savegamePath={path}","bios_path":"-b {path}"}},
      "save_contract":{"artifact_glob":"{saveDir}/{romBaseName}.sav","directory_key":"savegamePath","flush_triggers":["periodic"],"on_demand_flush_supported":false,"worst_case_loss_seconds":24},
      "exit_detection":{"clean":{"terminationStatus":0,"terminationReason":"exit"},"crash":{"terminationStatus":11,"terminationReason":"uncaughtSignal"},"killed":{"terminationStatus":9,"terminationReason":"uncaughtSignal"}}
    }
    """
}
