import SwiftUI
import AppKit

/// Central design-system tokens for the Mac client, binding on every
/// library/curation surface (03-UI-SPEC.md Spacing Scale, Typography,
/// Color roles; `SystemAccent`/`StatusToken` carry the deliberately disjoint
/// identity and state vocabularies shared with the web palette contract.
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
        static let height: CGFloat = 224
        static let cornerRadius: CGFloat = 12
    }

    /// Repeated app-owned shapes only. Standard controls should use native
    /// styling; unique artwork and layout geometry stay local to their view.
    enum Radius {
        static let tight: CGFloat = 4
        static let compact: CGFloat = 6
        static let standard: CGFloat = 8
    }

    /// Every icon-only control uses a 44×44px minimum interactive
    /// target on both platforms (QUAL-01 accessibility floor).
    enum InteractiveTarget {
        static let minimum: CGFloat = 44
    }

    /// Reused, cross-phase, for exactly one new purpose: the
    /// keyboard/controller focus ring — never for a system or a status.
    static let focusRing = Color(nsColor: .controlAccentColor)
    /// Delete-collection and remove-downloaded-copy confirmation buttons only.
    static let destructive = Color(hex: 0xEF4444)
    /// Semantic AppKit colors follow the user's macOS appearance, contrast,
    /// and accent selection instead of baking the Mac client into dark mode.
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textMuted = Color(nsColor: .secondaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
}

extension Font {
    /// A small semantic layer over the platform's SF system text styles.
    /// This keeps hierarchy consistent with native controls and avoids
    /// fixed-size app typography drifting away from macOS conventions.
    static let psBody = Font.body
    static let psLabel = Font.callout
    static let psLabelEmphasized = Font.callout.weight(.semibold)
    static let psHeading = Font.title3.weight(.semibold)
    static let psDisplay = Font.title.weight(.semibold)
}

extension Color {
    /// Builds a `Color` from a 24-bit hex literal (e.g. `0x38BDF8`) —
    /// Use for fixed project-owned palette roles. Prefer AppKit/SwiftUI
    /// semantic colors for appearance-dependent values.
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
