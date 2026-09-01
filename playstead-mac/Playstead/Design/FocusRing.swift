import SwiftUI

/// The one visible keyboard-focus treatment shared by production controls.
/// Selection remains a separate state owned by each control; this modifier
/// reads only actual SwiftUI focus ownership.
enum PlaysteadFocusRing {
    static let colorHex = "#38BDF8"
    static let color = Color(
        red: 0x38 / 255.0,
        green: 0xBD / 255.0,
        blue: 0xF8 / 255.0
    )
    static let lineWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 8

    static func opacity(isFocused: Bool) -> Double {
        isFocused ? 1 : 0
    }
}

private struct PlaysteadFocusableModifier: ViewModifier {
    let identifier: String
    @FocusState private var ownsFocus: Bool

    func body(content: Content) -> some View {
        content
            .focused($ownsFocus)
            .accessibilityIdentifier(identifier)
            .overlay {
                RoundedRectangle(cornerRadius: PlaysteadFocusRing.cornerRadius)
                    .stroke(PlaysteadFocusRing.color, lineWidth: PlaysteadFocusRing.lineWidth)
                    .opacity(PlaysteadFocusRing.opacity(isFocused: ownsFocus))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Adds stable identity, keyboard focus ownership, and the locked cyan ring.
    func playsteadFocusable(identifier: String) -> some View {
        modifier(PlaysteadFocusableModifier(identifier: identifier))
    }
}
