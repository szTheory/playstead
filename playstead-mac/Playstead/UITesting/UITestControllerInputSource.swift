#if UI_TESTING
import Foundation

/// One compiled, deterministic controller for the no-HID packaged UI journey.
/// This is selected only by DeterministicProfile.controllerRecovery; it has
/// no descriptor, identity, or report input from the process environment.
final class UITestControllerInputSource: ControllerInputSource {
    static let descriptor = ControllerDescriptor(
        id: "ui-test-controller",
        name: "Playstead Test Controller",
        availableInputs: ControllerDescriptor.defaultInputs
    )

    static let spareDescriptor = ControllerDescriptor(
        id: "ui-test-spare-controller", name: "Playstead Spare Controller",
        availableInputs: ControllerDescriptor.defaultInputs
    )
    private var spareConnected = false
    private(set) var isConnected = true
    private var onConnect: ((ControllerDescriptor) -> Void)?
    private var onDisconnect: ((ControllerDescriptor) -> Void)?
    private var onInput: ((ControllerInputEvent) -> Void)?

    var currentControllers: [ControllerDescriptor] {
        (isConnected ? [Self.descriptor] : []) + (spareConnected ? [Self.spareDescriptor] : [])
    }

    func startObserving(
        onConnect: @escaping (ControllerDescriptor) -> Void,
        onDisconnect: @escaping (ControllerDescriptor) -> Void,
        onInput: @escaping (ControllerInputEvent) -> Void
    ) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onInput = onInput
    }

    func pressA() {
        emit(input: "buttonA", active: true)
    }

    func releaseA() {
        emit(input: "buttonA", active: false)
    }

    func pressB() {
        emit(input: "buttonB", active: true)
    }

    func releaseB() {
        emit(input: "buttonB", active: false)
    }


    func pressUp() {
        emit(input: "dpadUp", active: true)
    }

    func releaseUp() {
        emit(input: "dpadUp", active: false)
    }

    func connectSpare() {
        guard !spareConnected else { return }
        spareConnected = true
        onConnect?(Self.spareDescriptor)
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        onDisconnect?(Self.descriptor)
    }

    func reconnect() {
        guard !isConnected else { return }
        isConnected = true
        onConnect?(Self.descriptor)
    }

    private func emit(input: String, active: Bool) {
        guard isConnected || spareConnected,
              ControllerDescriptor.defaultInputs.contains(input) else { return }
        onInput?(ControllerInputEvent(
            controllerID: isConnected ? Self.descriptor.id : Self.spareDescriptor.id,
            inputName: input,
            isActive: active
        ))
    }
}
#endif
