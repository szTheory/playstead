import Foundation
import GameController

/// One connected controller's identity and the fixed set of
/// adapter-relevant inputs it can report — enough for
/// `ControllerTestView` to show live presses and for
/// `ControllerMapping` to name a remap target. `id` is a stable
/// per-controller identifier synthesized once per physical controller
/// per app run (see `GCControllerInputSource`'s doc comment) — the same
/// physical controller reconnecting produces the same `id` within one
/// run, which is what makes "reconnecting restores controller input
/// with no relaunch" a testable claim rather than an assumption.
struct ControllerDescriptor: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let availableInputs: [String]

    /// The fixed set every descriptor reports — matches
    /// `ControllerMapping.defaultControllerInputs`, since a mapping can
    /// only ever target an input the controller actually exposes.
    static let defaultInputs = ControllerMapping.defaultControllerInputs
}

/// The controller half of the app's input picture — exactly one of
/// `.disconnected` or `.connected(descriptor)` at any moment, reflecting
/// the currently *assigned* controller, not merely whether any
/// controller exists. Two controllers connected at once still resolve
/// to this one state (D-14's single-active-controller scope); the
/// second remains selectable via `ControllerHost.assign`.
enum ControllerConnectionState: Equatable {
    case disconnected
    case connected(ControllerDescriptor)
}

/// What a surface may currently rely on for input. A Mac always offers
/// keyboard and pointer; controller availability tracks
/// `ControllerConnectionState`. This is the type any surface (and
/// eventually `ReadinessEngine`'s `hasController`/`hasKeyboard`
/// closures) consults so "the controller disconnected" is never
/// confused with "the user has no way to act" — the property that
/// makes a controller an enhancement, never a dependency.
struct InputPathAvailability: Equatable {
    let keyboardAvailable: Bool
    let pointerAvailable: Bool
    let controllerAvailable: Bool

    static func current(controllerConnected: Bool) -> InputPathAvailability {
        InputPathAvailability(keyboardAvailable: true, pointerAvailable: true, controllerAvailable: controllerConnected)
    }
}

/// Wraps the Game Controller framework's connect/disconnect
/// notifications behind a small, injectable protocol so tests can
/// simulate a controller appearing and vanishing with no physical
/// hardware. The plan 03-01 spike recorded controller recovery as
/// unproven for lack of hardware (03-SPIKE-REPORT.md probe 5) — this
/// abstraction is what lets the *logic* around that gap be fully,
/// honestly tested regardless of whether hardware is ever available in
/// the execution environment.
protocol ControllerInputSource: AnyObject {
    var currentControllers: [ControllerDescriptor] { get }
    func startObserving(
        onConnect: @escaping (ControllerDescriptor) -> Void,
        onDisconnect: @escaping (ControllerDescriptor) -> Void
    )
}

/// The production `ControllerInputSource`: wraps `GCController`'s
/// current controller list and its connect/disconnect notifications.
/// `GCController` exposes no public, stable "product identifier"
/// string, so `id` is synthesized once per physical `GCController`
/// instance (keyed by `ObjectIdentifier`, which is stable for the
/// lifetime of that specific connection) — good enough to distinguish
/// two simultaneously connected controllers and to recognize the same
/// physical controller across a disconnect/reconnect within one run,
/// which is everything this app's mapping and recovery logic need.
final class GCControllerInputSource: ControllerInputSource {
    private static var nextIndex = 0
    private var assignedIDs: [ObjectIdentifier: String] = [:]

    private func descriptor(for controller: GCController) -> ControllerDescriptor {
        let key = ObjectIdentifier(controller)
        let id: String
        if let existing = assignedIDs[key] {
            id = existing
        } else {
            id = "\(controller.vendorName ?? "Controller")-\(Self.nextIndex)"
            Self.nextIndex += 1
            assignedIDs[key] = id
        }
        return ControllerDescriptor(id: id, name: controller.vendorName ?? "Controller", availableInputs: ControllerDescriptor.defaultInputs)
    }

    var currentControllers: [ControllerDescriptor] {
        GCController.controllers().map(descriptor(for:))
    }

    func startObserving(
        onConnect: @escaping (ControllerDescriptor) -> Void,
        onDisconnect: @escaping (ControllerDescriptor) -> Void
    ) {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            onConnect(self.descriptor(for: controller))
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            onDisconnect(self.descriptor(for: controller))
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }
}

/// Publishes controller connect/disconnect/assignment state for every
/// surface that cares — settings, the live test view, and the
/// non-modal recovery banner. Constructed once as part of
/// `AppEnvironment` and registered for notifications at application
/// launch (never lazily inside a settings view), so a controller
/// connected before the window opens is already known the instant a
/// surface reads this type.
@MainActor
@Observable
final class ControllerHost {
    private(set) var connectedControllers: [ControllerDescriptor] = []
    private(set) var assignedControllerID: String?
    /// Live per-input press/release state for `ControllerTestView` —
    /// driven by `reportInput(_:active:)`, which production code wires
    /// to real `GCExtendedGamepad` element value-changed handlers and
    /// tests call directly to simulate a press with no hardware.
    private(set) var liveInputs: Set<String> = []
    /// True from the instant a previously assigned controller
    /// disconnects until the user dismisses the affordance or a
    /// controller becomes assigned again — drives
    /// `ControllerRecoveryBanner`'s visibility. Never modal: nothing
    /// else in this type disables any other operation while this is
    /// true.
    private(set) var showRecoveryBanner = false
    private(set) var lastDisconnectedControllerName: String?

    private let source: ControllerInputSource

    init(source: ControllerInputSource = GCControllerInputSource()) {
        self.source = source
        connectedControllers = source.currentControllers
        assignedControllerID = connectedControllers.first?.id
        source.startObserving(
            onConnect: { [weak self] descriptor in self?.handleConnect(descriptor) },
            onDisconnect: { [weak self] descriptor in self?.handleDisconnect(descriptor) }
        )
    }

    var connectionState: ControllerConnectionState {
        if let assignedControllerID, let descriptor = connectedControllers.first(where: { $0.id == assignedControllerID }) {
            return .connected(descriptor)
        }
        return .disconnected
    }

    var inputPathAvailability: InputPathAvailability {
        if case .connected = connectionState {
            return .current(controllerConnected: true)
        }
        return .current(controllerConnected: false)
    }

    var hasAnyController: Bool { !connectedControllers.isEmpty }

    /// Changes which connected controller is active. Always legal for
    /// any currently connected controller — a user with two controllers
    /// plugged in changes which one drives the game (D-14).
    func assign(controllerID: String) {
        guard connectedControllers.contains(where: { $0.id == controllerID }) else { return }
        assignedControllerID = controllerID
        showRecoveryBanner = false
    }

    func dismissRecoveryBanner() {
        showRecoveryBanner = false
    }

    /// Records a live button/axis press or release.
    func reportInput(_ name: String, active: Bool) {
        if active {
            liveInputs.insert(name)
        } else {
            liveInputs.remove(name)
        }
    }

    private func handleConnect(_ descriptor: ControllerDescriptor) {
        if !connectedControllers.contains(where: { $0.id == descriptor.id }) {
            connectedControllers.append(descriptor)
        }
        if assignedControllerID == nil {
            assignedControllerID = descriptor.id
        }
        if assignedControllerID == descriptor.id {
            showRecoveryBanner = false
        }
    }

    private func handleDisconnect(_ descriptor: ControllerDescriptor) {
        connectedControllers.removeAll { $0.id == descriptor.id }
        if assignedControllerID == descriptor.id {
            lastDisconnectedControllerName = descriptor.name
            showRecoveryBanner = true
            assignedControllerID = connectedControllers.first?.id
        }
    }
}
