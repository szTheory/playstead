import Foundation

/// The one definition of this device's display name for save-history
/// surfaces (D-37/D-39/D-50 through D-55) -- an origin-name slot fill,
/// never a new user-facing copy string. No device-name registry exists
/// on this client yet, so every surface that needs "this Mac's own
/// name" reads it from here rather than each defining its own literal.
enum SaveOriginNames {
    static let thisDevice = "This Mac"
}
