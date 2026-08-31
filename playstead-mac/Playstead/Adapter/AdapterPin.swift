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

struct AdapterSaveContract: Codable, Equatable {
    let artifactGlob: String
    let directoryKey: String
    let flushTriggers: [String]
    let onDemandFlushSupported: Bool
    let worstCaseLossSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case artifactGlob = "artifact_glob"
        case directoryKey = "directory_key"
        case flushTriggers = "flush_triggers"
        case onDemandFlushSupported = "on_demand_flush_supported"
        case worstCaseLossSeconds = "worst_case_loss_seconds"
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
