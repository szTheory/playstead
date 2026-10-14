import SwiftUI

/// Offers assign, per-input remap, and reset-to-defaults for the
/// currently connected controllers. Purely a projection over
/// `ControllerHost` plus a `ControllerMapping`/`ControllerMappingStore`
/// pair the caller supplies — this view never talks to
/// `ControllerHost`'s underlying `ControllerInputSource` directly.
struct ControllerSettingsView: View {
    let connectedControllers: [ControllerDescriptor]
    let assignedControllerID: String?
    let mapping: ControllerMapping
    let mappingError: String?
    var liveInputs: Set<String> = []
    var showsMappingControls = false
    let onAssign: (String) -> Void
    let onRemap: (String, String) -> Void
    let onReset: () -> Void
    let onOpenTestView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if connectedControllers.isEmpty {
                Text("No controller connected. Keyboard controls are available.")
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
#if UI_TESTING
                Button("Test controller", action: onOpenTestView)
                    .accessibilityIdentifier("playstead.controller.test.open")
#endif
            } else {
                assignmentSection
                if let controller = connectedControllers.first(where: { $0.id == assignedControllerID }),
                   let style = controller.buttonStyle, style != .generic {
                    ControllerDiagram(style: style, liveInputs: liveInputs, availableInputs: controller.availableInputs)
                }
                Button("Test controller", action: onOpenTestView)
                    .accessibilityIdentifier("playstead.controller.test.open")
                if showsMappingControls {
                    mappingSection
                    HStack {
                        Spacer()
                        Button("Reset to defaults", action: onReset)
                            .accessibilityIdentifier("playstead.controller.mapping.reset")
                    }
                } else {
                    Text("mGBA uses its own controller bindings. Playstead button remapping is unavailable for this adapter; configure controls in mGBA's settings.")
                        .font(.psLabel)
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }
            if let mappingError {
                Text(mappingError)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityIdentifier("playstead.controller.mapping-error")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controller settings")
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.controllerSettings)
    }

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Active controller").font(.psLabelEmphasized).foregroundStyle(DesignTokens.textPrimary)
            ForEach(connectedControllers) { controller in
                Button {
                    onAssign(controller.id)
                } label: {
                    HStack {
                        Image(systemName: controller.id == assignedControllerID ? "checkmark.circle.fill" : "circle")
                        Text(controller.name)
                    }
                }
                .accessibilityLabel(controller.id == assignedControllerID ? "\(controller.name), active" : "Use \(controller.name)")
            }
        }
    }

    private var buttonStyle: ControllerButtonStyle {
        connectedControllers.first(where: { $0.id == assignedControllerID })?.buttonStyle ?? .generic
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Button mapping").font(.psLabelEmphasized).foregroundStyle(DesignTokens.textPrimary)
            ForEach(ControllerMapping.adapterInputs, id: \.self) { adapterInput in
                HStack {
                    Text(adapterInput).font(.psLabel).foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Menu(mapping.controllerInput(for: adapterInput).map { ControllerInputLabel.displayName(for: $0, style: buttonStyle) } ?? "Unassigned") {
                        ForEach(ControllerDescriptor.defaultInputs, id: \.self) { candidate in
                            Button(ControllerInputLabel.displayName(for: candidate, style: buttonStyle)) { onRemap(adapterInput, candidate) }
                                .accessibilityIdentifier("playstead.controller.mapping.choice.\(candidate)")
                        }
                    }
                    .accessibilityLabel("\(adapterInput) mapped to \(mapping.controllerInput(for: adapterInput).map { ControllerInputLabel.displayName(for: $0, style: buttonStyle) } ?? "nothing")")
                    .accessibilityIdentifier("playstead.controller.mapping.\(adapterInput)")
                }
            }
        }
    }
}
