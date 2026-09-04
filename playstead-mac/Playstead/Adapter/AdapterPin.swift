import Foundation

/// The launch shape for the pinned emulator: where its executable lives
/// relative to the installed emulator directory, and the CLI argument
/// template with `{saveDir}`/`{romPath}` placeholders.
struct AdapterLaunch: Codable, Equatable {
    let executableRelativePath: String
    let argumentTemplate: [String]

    private enum CodingKeys: String, CodingKey {
        case executableRelativePath = "executable_relative_path"
        case argumentTemplate = "argument_template"
    }

    /// Substitutes `{romPath}` and `{saveDir}` in every template
    /// argument, returning the concrete argument array `Process` should
    /// receive.
    func renderedArguments(romPath: String, saveDir: String) -> [String] {
        argumentTemplate.map {
            $0.replacingOccurrences(of: "{romPath}", with: romPath)
                .replacingOccurrences(of: "{saveDir}", with: saveDir)
        }
    }
}

struct AdapterConfigInjection: Codable, Equatable {
    let mechanism: String
    let keys: [String: String]
}

/// One backup-medium entry in `AdapterSaveContract.media` — the byte
/// size the pinned adapter observes IS the medium's identity (D-24),
/// never something this client infers independently.
struct AdapterSaveMedium: Codable, Equatable {
    let id: String
    let bytes: Int
}

/// D-24: the additive fields below drive `SaveCompatibilityGate` (D-18,
/// D-19). Every one is a Swift `Optional` — the original five keys
/// (`artifactGlob` through `worstCaseLossSeconds`) are non-optional
/// `let`s and shipped before this plan, so an older pin JSON lacking
/// every new key must still decode with these fields `nil`. Swift's
/// synthesized `Decodable` already treats a missing key as `nil` for an
/// `Optional` property, so no custom `init(from:)` is needed here.
struct AdapterSaveContract: Codable, Equatable {
    let artifactGlob: String
    let directoryKey: String
    let flushTriggers: [String]
    let onDemandFlushSupported: Bool
    let worstCaseLossSeconds: Int

    /// `"battery"` in every Phase 4 pin (SEED-019's frozen vocabulary
    /// seam) — a future save-state adapter entry would declare
    /// `"state"` here with a wider `bindingFields` set, with zero
    /// client-side gate change.
    let saveKind: String?
    /// Every backup medium the pinned emulator's override database
    /// knows about — not only the proven one. `provenMedia` below is
    /// the honest subset.
    let media: [AdapterSaveMedium]?
    /// Whether the observed artifact byte size alone identifies the
    /// medium (true for GBA — SDK-string detection is a ROM-content
    /// fact, not something this client re-derives).
    let sizeIsMediumIdentity: Bool?
    let acceptsForeignMedium: Bool?
    /// A battery save is written by the game, not the emulator, so it
    /// is portable across emulator builds in principle — recorded as
    /// data, never consulted by the gate (emulator/core/version are
    /// provenance only, D-18).
    let portableAcrossEmulators: Bool?
    let maxArtifactBytes: Int?
    /// The subset of `media` actually observed and proven restorable by
    /// the plan 03-01 spike — `docs/SUPPORT-MATRIX.md`'s save-restore
    /// section names this honestly rather than claiming the whole list.
    let provenMedia: [String]?
    /// The binding tuple's field names, as this adapter declares them —
    /// `SaveCompatibilityGate` is generic over this list rather than
    /// hardcoding GBA's fields, which is the exact seam a future
    /// save-state adapter entry (SEED-019) widens without a client
    /// change.
    let bindingFields: [String]?
    /// Recorded for provenance (SEED-001) and never read by the gate.
    let provenanceFields: [String]?

    private enum CodingKeys: String, CodingKey {
        case artifactGlob = "artifact_glob"
        case directoryKey = "directory_key"
        case flushTriggers = "flush_triggers"
        case onDemandFlushSupported = "on_demand_flush_supported"
        case worstCaseLossSeconds = "worst_case_loss_seconds"
        case saveKind = "save_kind"
        case media
        case sizeIsMediumIdentity = "size_is_medium_identity"
        case acceptsForeignMedium = "accepts_foreign_medium"
        case portableAcrossEmulators = "portable_across_emulators"
        case maxArtifactBytes = "max_artifact_bytes"
        case provenMedia = "proven_media"
        case bindingFields = "binding_fields"
        case provenanceFields = "provenance_fields"
    }
}

/// The observed `(terminationStatus, terminationReason)` signature for
/// one exit category, exactly as the plan 03-01 spike measured it —
/// this client never guesses signal semantics independently.
struct AdapterExitSignature: Codable, Equatable {
    let terminationStatus: Int32
    let terminationReason: String
}

struct AdapterExitDetection: Codable, Equatable {
    let clean: AdapterExitSignature
    let crash: AdapterExitSignature
    let killed: AdapterExitSignature
}

/// The full pinned adapter contract, decoded from `03-ADAPTER-PIN.json`
/// (shipped as a bundle resource). No emulator version, flag name, or
/// config key appears as a literal anywhere else in the client — every
/// consumer reads it from here, so a re-run of the spike changes one
/// file.
struct AdapterPin: Codable, Equatable {
    let system: String
    let emulator: String
    let version: String
    let downloadURL: URL
    let sha256: String
    let launch: AdapterLaunch
    let configInjection: AdapterConfigInjection
    let saveContract: AdapterSaveContract
    let exitDetection: AdapterExitDetection

    private enum CodingKeys: String, CodingKey {
        case system, emulator, version, sha256, launch
        case downloadURL = "download_url"
        case configInjection = "config_injection"
        case saveContract = "save_contract"
        case exitDetection = "exit_detection"
    }

    enum LoadError: Error {
        case resourceMissing
    }

    /// Loads and decodes the pin from the app bundle. `bundle` is
    /// injectable for tests.
    static func load(bundle: Bundle = .main) throws -> AdapterPin {
        guard let url = bundle.url(forResource: "AdapterPin", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AdapterPin.self, from: data)
    }
}
