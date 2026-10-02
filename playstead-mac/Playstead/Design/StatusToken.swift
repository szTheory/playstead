import SwiftUI

/// Purely-state color vocabulary (03-UI-SPEC.md Status Ladder Palette) —
/// never conveys system identity. Must never share a literal value with
/// `SystemAccent` (D-13). `safeToEvict` is a real color token (the
/// storage view, plan 03-07, needs it) but is **not** a `LibraryStatus`
/// case — see that type's doc comment in `StatusSlotView.swift`.
enum StatusToken {
    private static let hexValues: [String: UInt32] = [
        "attention": 0xF59E0B,
        "missingDependency": 0xEA580C,
        "downloading": 0x0EA5E9,
        "queued": 0x9CA3AF,
        "verified": 0x16A34A,
        "serverOnly": 0x94A3B8,
        "safeToEvict": 0x78716C
    ]

    private static func color(_ role: String) -> Color {
        Color(hex: hexValues[role]!)
    }

    static let attention = color("attention")
    static let missingDependency = color("missingDependency")
    static let downloading = color("downloading")
    static let queued = color("queued")
    static let verified = color("verified")
    /// Retention is a storage policy, not a success state. Keep it neutral
    /// so the pin doesn't compete with the verified/playable checkmark.
    static let pinned = Color(nsColor: .secondaryLabelColor)
    static let serverOnly = color("serverOnly")
    static let safeToEvict = color("safeToEvict")

    /// Fixed palette values — used by `StatusLadderTests` to assert this
    /// vocabulary shares no value with `SystemAccent`'s. Pinned deliberately
    /// uses the system's secondary label color instead.
    static let allValues: Set<UInt32> = Set(hexValues.values)

    static func color(for status: LibraryStatus) -> Color {
        switch status {
        case .needsAttention: return attention
        case .missingDependency: return missingDependency
        case .downloading: return downloading
        case .queued: return queued
        case .pinned: return pinned
        case .verified: return verified
        case .serverOnly: return serverOnly
        }
    }
}
