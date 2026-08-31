import SwiftUI
import AppKit

/// Central design-system tokens for the Mac client, binding on every
/// library/curation surface (03-UI-SPEC.md Spacing Scale, Typography,
/// Color — inherited-from-Phase-1 roles only; `SystemAccent`/`StatusToken`
/// carry the two new, deliberately disjoint vocabularies this phase adds).
enum DesignTokens {
    /// Declared spacing values (multiples of 4), unchanged from Phase 1,
    /// now binding on the Mac client too — 1pt = 1px at the SwiftUI
    /// layout level, no additional platform scaling applied.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xl2: CGFloat = 48
        static let xl3: CGFloat = 64
    }

    /// Game card tiles are a fixed size, not derived from the spacing
    /// scale — D-16 requires zero skeletons and stable row heights for a
    /// 500-item library, only possible if tile geometry never depends on
    /// content length.
    enum CardGeometry {
        static let width: CGFloat = 280
        static let height: CGFloat = 158
    }

    /// Every icon-only control uses a 44×44px minimum interactive
    /// target on both platforms (QUAL-01 accessibility floor).
    enum InteractiveTarget {
        static let minimum: CGFloat = 44
    }

    /// Reused, cross-phase, for exactly one new purpose: the
    /// keyboard/controller focus ring — never for a system or a status.
    static let focusRing = Color(hex: 0x38BDF8)
    /// Delete-collection and remove-downloaded-copy confirmation buttons only.
    static let destructive = Color(hex: 0xEF4444)
    static let textPrimary = Color(hex: 0xF1F5F9)
    static let textMuted = Color(hex: 0x94A3B8)
    static let border = Color(hex: 0x334155)
}

extension Font {
    /// The 4-role type scale (03-UI-SPEC.md Typography). Only 2 weights
    /// exist system-wide: regular and semibold — Label alone appears at
    /// both, chosen per element by intent, never by role alone.
    static let psBody = Font.system(size: 16, weight: .regular)
    static let psLabel = Font.system(size: 14, weight: .regular)
    static let psLabelEmphasized = Font.system(size: 14, weight: .semibold)
    static let psHeading = Font.system(size: 20, weight: .semibold)
    static let psDisplay = Font.system(size: 28, weight: .semibold)
}

extension Color {
    /// Builds a `Color` from a 24-bit hex literal (e.g. `0x38BDF8`) —
    /// every design-token color in this phase is declared this way so
    /// the source of truth (03-UI-SPEC.md's hex table) is visually
    /// traceable in code review.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The frozen system-id registry (03-UI-SPEC.md Typography → System
/// monogram table): id, monogram, and display name, in the canonical
/// non-alphabetical order both the sidebar (Navigation & IA) and the
/// "show all systems" filter chips must render in — never a
/// designer-chosen abbreviation, never re-sorted.
enum SystemRegistry {
    struct Entry: Equatable {
        let id: String
        let monogram: String
        let displayName: String
    }

    static let all: [Entry] = [
        Entry(id: "gba", monogram: "GBA", displayName: "Game Boy Advance"),
        Entry(id: "gb", monogram: "GB", displayName: "Game Boy"),
        Entry(id: "gbc", monogram: "GBC", displayName: "Game Boy Color"),
        Entry(id: "nes", monogram: "NES", displayName: "NES"),
        Entry(id: "snes", monogram: "SNES", displayName: "Super Nintendo"),
        Entry(id: "md", monogram: "MD", displayName: "Sega Genesis"),
        Entry(id: "psx", monogram: "PSX", displayName: "PlayStation")
    ]

    static let unknown = Entry(id: "unknown", monogram: "?", displayName: "Unidentified")

    static func entry(for systemID: String) -> Entry {
        all.first(where: { $0.id == systemID }) ?? unknown
    }
}
