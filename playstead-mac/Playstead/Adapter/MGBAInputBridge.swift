import Foundation

/// The SDL 2.30.7 GameController-to-joystick binding returned by the same
/// SDL implementation used by the pinned mGBA frontend.
enum SDLRawBinding: Codable, Equatable, Hashable {
    case button(Int)
    case hat(index: Int, mask: Int)
    case axis(index: Int, sign: Int)
    case unbound

    private enum CodingKeys: String, CodingKey { case type, index, mask, sign }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decode(String.self, forKey: .type)
        switch type {
        case "button": self = .button(try values.decode(Int.self, forKey: .index))
        case "hat": self = .hat(index: try values.decode(Int.self, forKey: .index), mask: try values.decode(Int.self, forKey: .mask))
        case "axis": self = .axis(index: try values.decode(Int.self, forKey: .index), sign: try values.decode(Int.self, forKey: .sign))
        case "unbound": self = .unbound
        default: throw BridgeError.unsupportedBinding(type)
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .button(let index): try values.encode("button", forKey: .type); try values.encode(index, forKey: .index)
        case .hat(let index, let mask): try values.encode("hat", forKey: .type); try values.encode(index, forKey: .index); try values.encode(mask, forKey: .mask)
        case .axis(let index, let sign): try values.encode("axis", forKey: .type); try values.encode(index, forKey: .index); try values.encode(sign, forKey: .sign)
        case .unbound: try values.encode("unbound", forKey: .type)
        }
    }
}

struct SDLDeviceSnapshot: Codable, Equatable {
    let instanceID: Int
    let guid: String
    let name: String
    let bindings: [String: SDLRawBinding]
}

struct SDLInputEdge: Codable, Equatable {
    let instanceID: Int
    let input: String
    let pressed: Bool
    let generation: UInt64
}

private struct SDLHelperSnapshot: Decodable {
    let kind: String
    let generation: UInt64
    let devices: [SDLDeviceSnapshot]
}

/// Opens only the signed helper and dynamic library bundled by the app's
/// verified source build. One helper process supplies both the device
/// snapshot and its following event stream, so instance IDs/generation are
/// from the same SDL enumeration.
final class BundledSDLInputEventSource: SDLDeviceEventSource {
    private let lock = NSLock()
    private let helperURL: URL
    private let nonce = UUID().uuidString
    private var helper: Process?
    private var output: FileHandle?
    private var cachedSnapshot: (UInt64, [SDLDeviceSnapshot])?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        helperURL = bundleURL.appendingPathComponent("Contents/Helpers/playstead-sdl-input-bridge")
    }

    func devices() throws -> (generation: UInt64, devices: [SDLDeviceSnapshot]) {
        lock.lock()
        defer { lock.unlock() }
        if let cachedSnapshot { return (cachedSnapshot.0, cachedSnapshot.1) }
        let standardized = helperURL.standardizedFileURL
        let root = Bundle.main.bundleURL.standardizedFileURL.path + "/Contents/Helpers/"
        guard standardized.path.hasPrefix(root), FileManager.default.isExecutableFile(atPath: standardized.path) else {
            throw BridgeError.helperUnavailable
        }
        try Self.verifySignature(at: standardized)
        guard try Self.runVersionCheck(standardized) == "SDL 2.30.7" else { throw BridgeError.helperVersionMismatch }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = standardized
        process.arguments = ["--stream", nonce]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let inherited = ProcessInfo.processInfo.environment
        process.environment = inherited.filter { key, _ in key == "HOME" || key == "TMPDIR" || key.hasPrefix("SDL_") }
        do { try process.run() } catch { throw BridgeError.helperUnavailable }
        let handle = pipe.fileHandleForReading
        guard let line = Self.readLine(from: handle),
              let data = line.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(SDLHelperSnapshot.self, from: data),
              snapshot.kind == "snapshot", snapshot.devices.count <= 8 else {
            process.terminate()
            throw BridgeError.helperUnavailable
        }
        helper = process
        output = handle
        cachedSnapshot = (snapshot.generation, snapshot.devices)
        return (snapshot.generation, snapshot.devices)
    }

    /// A fresh helper process provides a launch-boundary snapshot. SDL's
    /// instance IDs are OS device-instance values and remain stable while a
    /// connected device is open; the GUID and typed bindings must also remain
    /// identical. This catches disconnect/reassignment before config write.
    func currentDevices() throws -> (generation: UInt64, devices: [SDLDeviceSnapshot]) {
        let standardized = helperURL.standardizedFileURL
        let root = Bundle.main.bundleURL.standardizedFileURL.path + "/Contents/Helpers/"
        guard standardized.path.hasPrefix(root), FileManager.default.isExecutableFile(atPath: standardized.path) else { throw BridgeError.helperUnavailable }
        try Self.verifySignature(at: standardized)
        guard try Self.runVersionCheck(standardized) == "SDL 2.30.7" else { throw BridgeError.helperVersionMismatch }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = standardized
        process.arguments = ["--snapshot"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.filter { key, _ in key == "HOME" || key == "TMPDIR" || key.hasPrefix("SDL_") }
        try process.run()
        let finished = DispatchSemaphore(value: 0)
        let outputLock = NSLock()
        var output = Data()
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock(); output = data; outputLock.unlock()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 2) == .success else {
            if process.isRunning { process.terminate() }
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw BridgeError.helperUnavailable
        }
        process.waitUntilExit()
        outputLock.lock(); let data = output; outputLock.unlock()
        guard process.terminationStatus == 0, data.count <= 65_536,
              let snapshot = try? JSONDecoder().decode(SDLHelperSnapshot.self, from: data),
              snapshot.kind == "snapshot", snapshot.devices.count <= 8 else { throw BridgeError.helperUnavailable }
        return (snapshot.generation, snapshot.devices)
    }

    func inputEdges() -> AsyncThrowingStream<SDLInputEdge, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [weak self] in
                guard let self else { continuation.finish(throwing: BridgeError.helperUnavailable); return }
                guard let output = self.output, let helper = self.helper else {
                    continuation.finish(throwing: BridgeError.helperUnavailable)
                    return
                }
                while !Task.isCancelled, let line = Self.readLine(from: output), let data = line.data(using: .utf8) {
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let kind = object["kind"] as? String else {
                        continuation.finish(throwing: BridgeError.helperUnavailable)
                        return
                    }
                    if kind == "invalidate" {
                        continuation.finish(throwing: BridgeError.staleAttestation)
                        return
                    }
                    guard kind == "edge" else {
                        continuation.finish(throwing: BridgeError.helperUnavailable)
                        return
                    }
                    guard object["nonce"] as? String == self.nonce else {
                        continuation.finish(throwing: BridgeError.challengeFailed("SDL helper nonce mismatch"))
                        return
                    }
                    guard let edge = try? JSONDecoder().decode(SDLInputEdge.self, from: data) else {
                        continuation.finish(throwing: BridgeError.helperUnavailable)
                        return
                    }
                    continuation.yield(edge)
                }
                continuation.finish(throwing: BridgeError.helperUnavailable)
                if helper.isRunning { helper.terminate() }
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.terminateHelper()
            }
        }
    }

    deinit { if let helper, helper.isRunning { helper.terminate() } }

    private func terminateHelper() {
        lock.lock()
        let running = helper?.isRunning == true
        let current = helper
        lock.unlock()
        guard running, let current else { return }
        current.terminate()
        // Closing the child closes the pipe and releases a reader blocked in
        // read(upToCount:). Bound this wait because an invalid helper must
        // never outlive the attestation session or the app.
        let deadline = Date().addingTimeInterval(0.5)
        while current.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if current.isRunning { kill(current.processIdentifier, SIGKILL) }
        let reapDeadline = Date().addingTimeInterval(0.5)
        while current.isRunning && Date() < reapDeadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    private static func readLine(from handle: FileHandle) -> String? {
        var bytes = Data()
        while let byte = try? handle.read(upToCount: 1), !byte.isEmpty {
            if byte[0] == 0x0A { return String(data: bytes, encoding: .utf8) }
            guard bytes.count < 65_536 else { return nil }
            bytes.append(byte[0])
        }
        return nil
    }

    private static func verifySignature(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BridgeError.helperUnavailable }
    }

    private static func runVersionCheck(_ url: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = url
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, bytes.count < 64,
              let result = String(data: bytes, encoding: .utf8) else { throw BridgeError.helperVersionMismatch }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AssignedInputEdge: Equatable {
    let controllerID: String
    let input: String
    let pressed: Bool
}

struct ControllerAttestation: Equatable {
    let controllerID: String
    let instanceID: Int
    let guid: String
    let generation: UInt64
    let bindings: [String: SDLRawBinding]
}

enum BridgeError: Error, Equatable, LocalizedError {
    case noSDLController
    case ambiguousSDLControllers
    case challengeFailed(String)
    case staleAttestation
    case missingBinding(String)
    case duplicateBinding(String)
    case unsupportedBinding(String)
    case invalidMapping(String)
    case helperUnavailable
    case helperVersionMismatch

    var errorDescription: String? {
        switch self {
        case .noSDLController: "No SDL controller is connected. Connect the assigned controller and retry."
        case .ambiguousSDLControllers: "More than one SDL controller is connected. Disconnect extras and retry."
        case .challengeFailed(let reason): "Controller identity challenge failed (\(reason)). Keep the assigned controller connected and retry."
        case .staleAttestation: "Controller assignment changed. Reconnect and retry the input challenge."
        case .missingBinding(let name): "The active SDL profile does not bind \(name). Update the SDL controller mapping and retry."
        case .duplicateBinding(let name): "Multiple game actions use the same raw input (\(name)); choose distinct controller inputs."
        case .unsupportedBinding(let name): "Unsupported SDL binding type: \(name)."
        case .invalidMapping(let reason): "The saved controller mapping is invalid: \(reason). Correct the mapping and retry."
        case .helperUnavailable: "The signed SDL input helper is missing or cannot be verified. Reinstall Playstead."
        case .helperVersionMismatch: "The bundled SDL helper does not match SDL 2.30.7. Reinstall Playstead."
        }
    }
}

/// Shared launch gate used by the game row and deterministic tests. The
/// resume callback runs only after the production challenge succeeds and the
/// presenting task has not been cancelled (including sheet dismissal).
enum ControllerChallengeLaunchCoordinator {
    @MainActor
    static func perform(
        challenge: () async throws -> Void,
        resumeLaunch: () async -> Void
    ) async throws {
        try Task.checkCancellation()
        try await challenge()
        try Task.checkCancellation()
        await resumeLaunch()
    }
}

/// Holds cross-launch identity proof for one assigned-controller session.
/// Assignment/disconnect observers invalidate it; game relaunches reuse the
/// challenge result and perform a fresh SDL snapshot check at the spawn gate.
@MainActor
final class ControllerAttestationSession {
    private(set) var value: (ControllerAttestation, SDLDeviceSnapshot)?

    func attestation(
        establishingWith challenge: () async throws -> (ControllerAttestation, SDLDeviceSnapshot)
    ) async throws -> (ControllerAttestation, SDLDeviceSnapshot) {
        if let value { return value }
        let established = try await challenge()
        value = established
        return established
    }

    func invalidate() { value = nil }
}

protocol SDLDeviceEventSource {
    func devices() throws -> (generation: UInt64, devices: [SDLDeviceSnapshot])
    func inputEdges() -> AsyncThrowingStream<SDLInputEdge, Error>
}

@MainActor
protocol AssignedControllerEventSource {
    var assignedControllerID: String? { get }
    func inputEdges() -> AsyncStream<AssignedInputEdge>
}

/// Event-level identity proof. Framework clock values are deliberately not
/// compared: both input sources are consumed by this actor's monotonic clock.
enum MGBAInputBridge {
    private struct EdgeSignature: Equatable { let input: String; let pressed: Bool }
    static let sdlVersion = "2.30.7"
    static let challengeInputs = ["buttonA", "leftShoulder"]

    private struct Received<Value> {
        let value: Value
        let receivedAt: ContinuousClock.Instant
    }
    private enum ChallengeResult { case assigned([Received<AssignedInputEdge>]); case sdl([Received<SDLInputEdge>]) }

    static func attest(assignedSource: AssignedControllerEventSource, sdlSource: SDLDeviceEventSource) async throws -> (ControllerAttestation, SDLDeviceSnapshot) {
        guard let assignedID = await assignedSource.assignedControllerID else { throw BridgeError.challengeFailed("no assigned controller") }
        let (generation, devices) = try sdlSource.devices()
        let device = try requireUniqueDevice(devices)
        let result = try await withThrowingTaskGroup(of: ChallengeResult.self) { group in
            group.addTask {
                let events = await assignedSource.inputEdges()
                let edges = try await Self.collectAssigned(events)
                return .assigned(edges)
            }
            group.addTask {
                let edges = try await Self.collectSDL(sdlSource.inputEdges())
                return .sdl(edges)
            }
            group.addTask {
                try await ContinuousClock().sleep(for: .seconds(8))
                throw BridgeError.challengeFailed("challenge timed out")
            }
            var assigned: [Received<AssignedInputEdge>]?
            var sdl: [Received<SDLInputEdge>]?
            while let item = try await group.next() {
                switch item {
                case .assigned(let edges): assigned = edges
                case .sdl(let edges): sdl = edges
                }
                if let assigned, let sdl {
                    group.cancelAll()
                    let proof = try attest(controllerID: assignedID, device: device, generation: generation, gameControllerEdges: assigned.map(\.value), sdlEdges: sdl.map(\.value))
                    guard assigned.count == sdl.count else { throw BridgeError.challengeFailed("input edge count mismatch") }
                    for index in assigned.indices {
                        let left = assigned[index].receivedAt
                        let right = sdl[index].receivedAt
                        let skew = left <= right ? left.duration(to: right) : right.duration(to: left)
                        guard skew <= .seconds(1) else { throw BridgeError.challengeFailed("controller event timing did not correlate") }
                    }
                    return proof
                }
            }
            throw BridgeError.challengeFailed("input stream ended before the sequence completed")
        }
        return (result, device)
    }

    private static func collectAssigned(_ events: AsyncStream<AssignedInputEdge>) async throws -> [Received<AssignedInputEdge>] {
        var result: [Received<AssignedInputEdge>] = []
        for await event in events {
            result.append(Received(value: event, receivedAt: ContinuousClock().now))
            if result.count == 4 { return result }
        }
        throw BridgeError.challengeFailed("assigned controller input stream ended")
    }

    private static func collectSDL(_ events: AsyncThrowingStream<SDLInputEdge, Error>) async throws -> [Received<SDLInputEdge>] {
        var result: [Received<SDLInputEdge>] = []
        for try await event in events {
            result.append(Received(value: event, receivedAt: ContinuousClock().now))
            if result.count == 4 { return result }
        }
        throw BridgeError.challengeFailed("SDL input stream ended")
    }

    static func requireUniqueDevice(_ devices: [SDLDeviceSnapshot]) throws -> SDLDeviceSnapshot {
        guard !devices.isEmpty else { throw BridgeError.noSDLController }
        guard devices.count == 1 else { throw BridgeError.ambiguousSDLControllers }
        return devices[0]
    }

    static func attest(
        controllerID: String,
        device: SDLDeviceSnapshot,
        generation: UInt64,
        gameControllerEdges: [AssignedInputEdge],
        sdlEdges: [SDLInputEdge]
    ) throws -> ControllerAttestation {
        guard !controllerID.isEmpty else { throw BridgeError.challengeFailed("no assigned controller") }
        guard gameControllerEdges.allSatisfy({ $0.controllerID == controllerID }) else {
            throw BridgeError.challengeFailed("input came from an unassigned controller")
        }
        guard sdlEdges.allSatisfy({ $0.instanceID == device.instanceID && $0.generation == generation }) else {
            throw BridgeError.challengeFailed("input came from another SDL instance or enumeration")
        }
        let expected = challengeInputs.flatMap { [EdgeSignature(input: $0, pressed: true), EdgeSignature(input: $0, pressed: false)] }
        let game = gameControllerEdges.map { EdgeSignature(input: $0.input, pressed: $0.pressed) }
        let sdl = sdlEdges.map { EdgeSignature(input: $0.input, pressed: $0.pressed) }
        guard game == expected, sdl == expected else {
            throw BridgeError.challengeFailed("expected A press/release then left shoulder press/release")
        }
        return ControllerAttestation(controllerID: controllerID, instanceID: device.instanceID, guid: device.guid, generation: generation, bindings: device.bindings)
    }

    static func config(mapping: ControllerMapping, attestation: ControllerAttestation, currentControllerID: String, generation: UInt64, device: SDLDeviceSnapshot) throws -> String {
        guard attestation.controllerID == currentControllerID,
              attestation.instanceID == device.instanceID,
              attestation.guid == device.guid,
              attestation.generation == generation,
              attestation.bindings == device.bindings else { throw BridgeError.staleAttestation }
        guard mapping.mappings.count == ControllerMapping.adapterInputs.count,
              Set(mapping.mappings.map(\.adapterInput)) == Set(ControllerMapping.adapterInputs),
              Set(mapping.mappings.map(\.adapterInput)).count == mapping.mappings.count else {
            throw BridgeError.invalidMapping("expected each of the ten GBA inputs exactly once")
        }
        let keyNames = ["A": "keyA", "B": "keyB", "L": "keyL", "R": "keyR", "Start": "keyStart", "Select": "keySelect", "Up": "keyUp", "Down": "keyDown", "Left": "keyLeft", "Right": "keyRight"]
        let gbaKeyIndex = ["A": 0, "B": 1, "Select": 2, "Start": 3, "Right": 4, "Left": 5, "Up": 6, "Down": 7, "R": 8, "L": 9]
        var rows: [String: String] = [:]
        var rawOwners: [String: String] = [:]
        for item in mapping.mappings {
            guard let configKey = keyNames[item.adapterInput] else { throw BridgeError.invalidMapping(item.adapterInput) }
            guard let gbaIndex = gbaKeyIndex[item.adapterInput] else { throw BridgeError.invalidMapping(item.adapterInput) }
            let bindingName = Self.sdlBindingName(forControllerInput: item.controllerInput)
            guard let binding = device.bindings[bindingName], binding != .unbound else { throw BridgeError.missingBinding(bindingName) }
            let raw: String
            switch binding {
            case .button(let index): raw = "button:\(index)"
            case .hat(let index, let mask): raw = "hat:\(index):\(mask)"
            case .axis(let index, let sign):
                guard sign == -1 || sign == 1 else { throw BridgeError.unsupportedBinding("axis sign \(sign)") }
                raw = "axis:\(index):\(sign)"
            case .unbound: throw BridgeError.missingBinding(bindingName)
            }
            if let previous = rawOwners[raw] { throw BridgeError.duplicateBinding("\(previous) and \(item.adapterInput) → \(raw)") }
            rawOwners[raw] = item.adapterInput
            switch binding {
            case .button(let index): rows[configKey] = String(index)
            case .hat(let index, let mask):
                let direction: String
                switch mask {
                case 1: direction = "Up"
                case 2: direction = "Right"
                case 4: direction = "Down"
                case 8: direction = "Left"
                default: throw BridgeError.unsupportedBinding("hat mask \(mask); expected one cardinal direction")
                }
                rows["hat\(index)\(direction)"] = String(gbaIndex)
            case .axis(let index, let sign):
                guard sign == -1 || sign == 1 else { throw BridgeError.unsupportedBinding("axis sign \(sign)") }
                rows["axis\(item.adapterInput)Axis"] = "\(sign < 0 ? "-" : "+")\(index)"
                rows["axis\(item.adapterInput)Value"] = "16384"
            case .unbound: throw BridgeError.missingBinding(bindingName)
            }
        }
        // mGBA's frontend permits both raw D-pad bindings and axis-based
        // stick bindings for the same logical direction. Keep the stick
        // that was already observed working while user remaps only buttons.
        if let xBinding = device.bindings["leftX"], let yBinding = device.bindings["leftY"] {
            guard case .axis(let x, let xSign) = xBinding,
                  case .axis(let y, let ySign) = yBinding,
                  (xSign == -1 || xSign == 1), (ySign == -1 || ySign == 1) else {
                throw BridgeError.unsupportedBinding("left stick axis binding")
            }
            rows["axisLeftAxis"] = "\(xSign > 0 ? "-" : "+")\(x)"
            rows["axisLeftValue"] = "16384"
            rows["axisRightAxis"] = "\(xSign > 0 ? "+" : "-")\(x)"
            rows["axisRightValue"] = "16384"
            rows["axisUpAxis"] = "\(ySign > 0 ? "-" : "+")\(y)"
            rows["axisUpValue"] = "16384"
            rows["axisDownAxis"] = "\(ySign > 0 ? "+" : "-")\(y)"
            rows["axisDownValue"] = "16384"
        } else if device.bindings["leftX"] != nil || device.bindings["leftY"] != nil {
            throw BridgeError.missingBinding("complete left stick axes")
        }
        return "[gba.input.SDLB]\n" + rows.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
    }

    static func sdlBindingName(forControllerInput input: String) -> String {
        switch input {
        case "buttonMenu": "buttonStart"
        case "buttonOptions": "buttonBack"
        default: input
        }
    }

    static func writePrivateConfig(_ content: String, under root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = root.appendingPathComponent("playstead-mgba-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let mgba = directory.appendingPathComponent("mgba", isDirectory: true)
        try FileManager.default.createDirectory(at: mgba, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = mgba.appendingPathComponent("config.ini")
        try Data(content.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return directory
    }
}
