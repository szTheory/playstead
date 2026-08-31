import Foundation

/// One adapter input (named by this app's own fixed vocabulary — never
/// the pin's literal CLI syntax, which `AdapterHost` alone renders)
/// mapped to one controller input element name (e.g. `"buttonA"`,
/// `"dpadUp"`). `ControllerMapping` is built from these;
/// `AdapterHost.renderedLaunchArguments` is what turns them into the
/// actual configuration the emulator receives.
struct MappedInput: Codable, Equatable {
    let adapterInput: String
    let controllerInput: String
}

/// A controller's full button/axis mapping, keyed by that controller's
/// own stable product identifier so a user's remap follows their
/// physical controller — persisted by `ControllerMappingStore` and
/// injected by `AdapterHost` at launch through the pin's
/// `config_injection` mechanism (D-14).
struct ControllerMapping: Codable, Equatable {
    let controllerProductID: String
    let mappings: [MappedInput]

    /// The fixed adapter input vocabulary this mapping always covers —
    /// the ten inputs a two-button, one-d-pad handheld needs.
    /// `ControllerSettingsView` and `ControllerTestView` both walk this
    /// list in this order so every surface presents inputs identically.
    static let adapterInputs: [String] = [
        "Up", "Down", "Left", "Right", "A", "B", "L", "R", "Start", "Select"
    ]

    /// `GCExtendedGamepad`'s own default element names, in
    /// `adapterInputs` order — the out-of-the-box mapping for a
    /// controller nobody has remapped yet.
    static let defaultControllerInputs: [String] = [
        "dpadUp", "dpadDown", "dpadLeft", "dpadRight",
        "buttonA", "buttonB", "leftShoulder", "rightShoulder",
        "buttonMenu", "buttonOptions"
    ]

    /// The out-of-the-box mapping for a controller product identifier
    /// nobody has remapped yet — every adapter input mapped to
    /// `GCExtendedGamepad`'s own default element, so a user who never
    /// opens settings still gets a fully populated, sensible mapping.
    static func defaultMapping(controllerProductID: String) -> ControllerMapping {
        let mapped = zip(adapterInputs, defaultControllerInputs).map {
            MappedInput(adapterInput: $0, controllerInput: $1)
        }
        return ControllerMapping(controllerProductID: controllerProductID, mappings: mapped)
    }

    /// Returns a copy with `adapterInput`'s mapped controller input
    /// replaced by `controllerInput` — every other entry unchanged.
    func remapping(adapterInput: String, to controllerInput: String) -> ControllerMapping {
        var updated = mappings
        if let index = updated.firstIndex(where: { $0.adapterInput == adapterInput }) {
            updated[index] = MappedInput(adapterInput: adapterInput, controllerInput: controllerInput)
        } else {
            updated.append(MappedInput(adapterInput: adapterInput, controllerInput: controllerInput))
        }
        return ControllerMapping(controllerProductID: controllerProductID, mappings: updated)
    }

    func controllerInput(for adapterInput: String) -> String? {
        mappings.first(where: { $0.adapterInput == adapterInput })?.controllerInput
    }
}
