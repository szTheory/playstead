import SwiftUI

/// Hides systems with zero asset sets behind one control whose label
/// always states the hidden count (03-UI-SPEC.md Navigation & IA,
/// LIBR-04's literal mechanism — emptiness-driven, never a persisted
/// user preference toggle). Adapter/BIOS/controller settings never
/// appear here or anywhere in library chrome.
struct ShowAllSystemsControl: View {
    let hiddenCount: Int
    @Binding var isExpanded: Bool

    static func label(hiddenCount: Int, isExpanded: Bool) -> String {
        isExpanded ? "Hide empty systems" : "Show all systems (\(hiddenCount) hidden)"
    }

    var body: some View {
        if hiddenCount > 0 {
            let text = Self.label(hiddenCount: hiddenCount, isExpanded: isExpanded)
            Button(text) {
                isExpanded.toggle()
            }
            .accessibilityLabel(text)
        }
    }
}
