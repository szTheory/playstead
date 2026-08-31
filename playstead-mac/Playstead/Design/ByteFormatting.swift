import Foundation

/// The single shared byte-count formatter/formatting function for every
/// storage-related view (`QuotaSettingsView`, `ReclaimPromptView`,
/// `StorageView`) — previously each view declared its own private,
/// identical `ByteCountFormatter`/`formatBytes` pair, so any future
/// change (count style, localization, an edge-case fix) had to be made
/// three times, with a fourth storage view likely to re-copy it again
/// rather than discover this one.
enum ByteFormatting {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatBytes(_ bytes: Int) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }
}
