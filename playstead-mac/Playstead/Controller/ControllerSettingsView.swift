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
    var onAssign: (String) -> Void = { _ in }
    var onRemap: (String, String) -> Void = { _, _ in }
    var onReset: () -> Void = {}
    var onOpenTestView: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if connectedControllers.isEmpty {
                Text("No controller connected. Keyboard and pointer remain fully available.")
                    .font(.psBody)
                    .foregroundStyle(DesignTokens.textMuted)
            } else {
                assignmentSection
                mappingSection
                HStack {
                    Button("Test controller", action: onOpenTestView)
                    Spacer()
                    Button("Reset to defaults", action: onReset)
                }
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

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Button mapping").font(.psLabelEmphasized).foregroundStyle(DesignTokens.textPrimary)
            ForEach(ControllerMapping.adapterInputs, id: \.self) { adapterInput in
                HStack {
                    Text(adapterInput).font(.psLabel).foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Menu(mapping.controllerInput(for: adapterInput) ?? "Unassigned") {
                        ForEach(ControllerDescriptor.defaultInputs, id: \.self) { candidate in
                            Button(candidate) { onRemap(adapterInput, candidate) }
                        }
                    }
                    .accessibilityLabel("\(adapterInput) mapped to \(mapping.controllerInput(for: adapterInput) ?? "nothing")")
                }
            }
        }
    }
}
