import SwiftUI

/// Purely-identity color vocabulary (03-UI-SPEC.md System Identity
/// Palette) — never conveys state, health, or urgency. Used only for the
/// monogram tile background and, at reduced opacity, the meta-line system
/// chip. Must never share a literal value with `StatusToken` (D-13).
enum SystemAccent {
    private static let hexValues: [String: UInt32] = [
        "gba": 0x6366F1,
        "gb": 0x65A30D,
        "gbc": 0x0D9488,
        "nes": 0xB91C1C,
        "snes": 0xA21CAF,
        "md": 0x1D4ED8,
        "psx": 0x57534E,
        "unknown": 0x64748B
    ]

    static func color(for systemID: String) -> Color {
        Color(hex: hexValues[systemID] ?? hexValues["unknown"]!)
    }

    /// Every declared value — used by `StatusLadderTests` to assert this
    /// vocabulary shares no value with `StatusToken`'s.
    static let allValues: Set<UInt32> = Set(hexValues.values)
}
