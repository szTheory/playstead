import SwiftUI

/// A standard text field for free-text search, reachable by keyboard and
/// pointer (03-UI-SPEC.md Navigation & IA: controller text entry is
/// deliberately not offered this phase — `FilterChipRow` is the
/// controller path to narrowing the library; keyboard/pointer remains
/// the path to arbitrary text).
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        TextField("Search your library", text: $text)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Search your library")
    }
}
