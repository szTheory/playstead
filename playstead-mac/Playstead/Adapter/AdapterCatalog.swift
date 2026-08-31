import Foundation

/// Everything the interface can honestly say about the one adapter this
/// phase supports, derived entirely from `AdapterPin` — no adapter fact
/// (version, digest, save behaviour) is ever restated as a literal here.
/// A restated fact would silently diverge from the spike's evidence the
/// first time the pin is refreshed.
struct AdapterDescriptor: Equatable {
    let system: String
    let emulatorName: String
    let version: String
    let downloadURL: URL
    let expectedSHA256: String
    /// The content-file extensions this adapter accepts, derived from the
    /// pinned system id itself rather than a hardcoded emulator-specific
    /// list.
    let acceptedContentTypes: [String]
    /// Whether a BIOS file is a hard requirement to launch at all. The
    /// spike's BIOS probe proved a no-BIOS launch succeeds via the
    /// adapter's own built-in high-level implementation, so this is
    /// `false` for the pinned adapter — a BIOS is an optional fidelity
    /// upgrade, never a launch blocker.
    let biosRequired: Bool
    /// Whether this adapter's config-injection mechanism accepts a BIOS
    /// path at all (read from the pin's own declared injection keys,
    /// never assumed).
    let biosInjectionSupported: Bool
    let saveContract: AdapterSaveContract

    init(pin: AdapterPin) {
        self.system = pin.system
        self.emulatorName = pin.emulator
        self.version = pin.version
        self.downloadURL = pin.downloadURL
        self.expectedSHA256 = pin.sha256
        self.acceptedContentTypes = [".\(pin.system)"]
        self.biosRequired = false
        self.biosInjectionSupported = pin.configInjection.keys["bios_path"] != nil
        self.saveContract = pin.saveContract
    }
}

/// Exposes the single adapter this phase supports. A thin, testable
/// wrapper over `AdapterPin` so callers never decode the pin themselves.
struct AdapterCatalog {
    let pin: AdapterPin

    init(pin: AdapterPin) {
        self.pin = pin
    }

    var descriptor: AdapterDescriptor {
        AdapterDescriptor(pin: pin)
    }
}
