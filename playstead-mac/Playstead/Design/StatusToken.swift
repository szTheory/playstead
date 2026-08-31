import SwiftUI

/// Purely-state color vocabulary (03-UI-SPEC.md Status Ladder Palette) —
/// never conveys system identity. Must never share a literal value with
/// `SystemAccent` (D-13). `safeToEvict` is a real color token (the
/// storage view, plan 03-07, needs it) but is **not** a `LibraryStatus`
/// case — see that type's doc comment in `StatusSlotView.swift`.
enum StatusToken {
    static let attention = Color(hex: 0xF59E0B)
    static let missingDependency = Color(hex: 0xEA580C)
    static let downloading = Color(hex: 0x0EA5E9)
    static let queued = Color(hex: 0x9CA3AF)
    static let verified = Color(hex: 0x16A34A)
    static let pinned = Color(hex: 0x15803D)
    static let serverOnly = Color(hex: 0x94A3B8)
    static let safeToEvict = Color(hex: 0x78716C)

    /// Every declared value — used by `StatusLadderTests` to assert this
    /// vocabulary shares no value with `SystemAccent`'s.
    static let allValues: Set<UInt32> = [
        0xF59E0B, 0xEA580C, 0x0EA5E9, 0x9CA3AF, 0x16A34A, 0x15803D, 0x94A3B8, 0x78716C
    ]

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
