import Foundation

/// Presentation labels are separate from the stable input identifiers.
/// Typed profiles choose physical labels without guessing from vendor names.
enum ControllerButtonStyle: String, Codable {
    case generic, dualSense, dualShock, xbox

    var isPlayStation: Bool { self == .dualSense || self == .dualShock }
}

enum ControllerInputLabel {
    static func displayName(for input: String, style: ControllerButtonStyle = .generic) -> String {
        if style.isPlayStation {
            switch input {
            case "buttonA": return "Cross ×"
            case "buttonB": return "Circle ○"
            case "buttonX": return "Square □"
            case "buttonY": return "Triangle △"
            case "leftShoulder": return "L1 · Left shoulder"
            case "rightShoulder": return "R1 · Right shoulder"
            case "buttonMenu": return "Options"
            case "buttonOptions": return style == .dualSense ? "Create" : "Share"
            default: break
            }
        } else if style == .xbox {
            switch input {
            case "buttonA": return "A"
            case "buttonB": return "B"
            case "buttonX": return "X"
            case "buttonY": return "Y"
            case "leftShoulder": return "LB · Left bumper"
            case "rightShoulder": return "RB · Right bumper"
            case "buttonOptions": return "View"
            default: break
            }
        }
        return switch input {
        case "dpadUp": "D-pad Up"
        case "dpadDown": "D-pad Down"
        case "dpadLeft": "D-pad Left"
        case "dpadRight": "D-pad Right"
        case "buttonA": "Lower face button"
        case "buttonB": "Right face button"
        case "buttonX": "Left face button"
        case "buttonY": "Upper face button"
        case "leftShoulder": "Left shoulder"
        case "rightShoulder": "Right shoulder"
        case "buttonMenu": "Menu"
        case "buttonOptions": "Options"
        default: input
        }
    }
}

/// One adapter input (named by this app's own fixed vocabulary — never
/// the emulator's literal SDL input configuration)
/// mapped to one controller input element name (e.g. `"buttonA"`,
/// `"dpadUp"`). `ControllerMapping` is built from these;
/// A future SDL binding bridge must translate them to the numeric
/// joystick codes that mGBA's input configuration consumes.
struct MappedInput: Codable, Equatable {
    let adapterInput: String
    let controllerInput: String
}

/// A controller's full button/axis mapping, keyed by that controller's
/// own stable product identifier so a user's remap follows their
/// physical controller — persisted by `ControllerMappingStore`.
/// The pinned mGBA adapter does not yet apply these values to gameplay.
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
