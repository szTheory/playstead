#if UI_TESTING
import Foundation

@MainActor
final class UITestProfileSession {
    let fixture: DeterministicProfileFixture?
    let environment: AppEnvironment

    init(fixture: DeterministicProfileFixture?, environment: AppEnvironment) {
        self.fixture = fixture
        self.environment = environment
    }

    deinit {
        if let fixture, !fixture.preservesRootForRelaunch {
            try? fixture.cleanup()
        }
    }
}

/// Fail-closed bridge from the process environment to one finite profile.
/// The selector is a name only; no root, SQL, JSON, or fixture bytes are accepted.
enum UITestBootstrap {
    static let modeKey = "PLAYSTEAD_UI_TESTING"
    static let profileKey = "PLAYSTEAD_UI_TEST_PROFILE"
    static let sessionIDKey = "PLAYSTEAD_UI_TEST_SESSION_ID"
    static let liveServerKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER"
    static let liveRootKey = "PLAYSTEAD_UI_TEST_LIVE_ROOT"
    static let handoffKey = "PLAYSTEAD_UI_TEST_CREDENTIAL_HANDOFF"
    static let keychainKey = "PLAYSTEAD_UI_TEST_KEYCHAIN"
    static let keychainServiceKey = "PLAYSTEAD_UI_TEST_KEYCHAIN_SERVICE"

    static func isRequested(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[modeKey] == "1"
    }

    @MainActor
    static func makeSession(
        environment processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> UITestProfileSession {
        guard isRequested(environment: processEnvironment) else {
            throw DeterministicProfileError.missingProfile
        }
        if processEnvironment[liveServerKey] == "1" {
            return try makeLiveServerSession(environment: processEnvironment)
        }
        let profile = try DeterministicProfile.parse(processEnvironment[profileKey])
        let fixture = try profile.makeFixture(sessionID: processEnvironment[sessionIDKey])
        let appEnvironment = AppEnvironment(
            uiTestingPaths: fixture.paths,
            localStore: fixture.localStore,
            reachability: Reachability(startOnline: false, monitorAutomatically: false)
        )
        appEnvironment.blockExternalIOForUITesting()
        // makeFixture validates a fresh seed exactly and validates a reopened
        // curation session against its durable inventory invariants. Requiring
        // fresh positions again here would reject the reorder state relaunch is
        // specifically responsible for proving.
        return UITestProfileSession(fixture: fixture, environment: appEnvironment)
    }

    private struct CredentialHandoff: Decodable {
        let deviceID: String
        let baseURL: URL
        let credential: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case baseURL = "base_url"
            case credential
        }
    }

    @MainActor
    private static func makeLiveServerSession(
        environment: [String: String]
    ) throws -> UITestProfileSession {
        let root = try ownedURL(environment[liveRootKey], label: "live root")
        let keychainURL = try containedURL(environment[keychainKey], root: root, label: "Keychain")
        let service = try validatedService(environment[keychainServiceKey])
        let keychain = try KeychainStore.uiTestingStore(service: service, fileURL: keychainURL)

        if let rawHandoff = environment[handoffKey] {
            let handoffURL = try containedURL(rawHandoff, root: root, label: "credential handoff")
            let attributes = try FileManager.default.attributesOfItem(atPath: handoffURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw DeterministicProfileError.invalidFixture
            }
            let data = try Data(contentsOf: handoffURL, options: [.mappedIfSafe])
            guard data.count > 0, data.count <= 4_096 else {
                throw DeterministicProfileError.invalidFixture
            }
            let handoff = try JSONDecoder().decode(CredentialHandoff.self, from: data)
            try FileManager.default.removeItem(at: handoffURL)

            let result = keychain.storeCredential(
                PairingCredential(
                    deviceID: handoff.deviceID,
                    baseURL: handoff.baseURL,
                    token: handoff.credential
                )
            )
            guard case .success = result,
                  keychain.loadCredential() == PairingCredential(
                    deviceID: handoff.deviceID,
                    baseURL: handoff.baseURL,
                    token: handoff.credential
                  ) else {
                throw DeterministicProfileError.invalidFixture
            }
        } else if keychain.loadCredential() == nil {
            throw DeterministicProfileError.invalidFixture
        }

        let paths = AppPaths(root: root)
        let localStore = try LocalStore(paths: paths)
        let appEnvironment = AppEnvironment(
            paths: paths,
            apiClient: APIClient(keychain: keychain),
            reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
        return UITestProfileSession(fixture: nil, environment: appEnvironment)
    }

    private static func ownedURL(_ raw: String?, label: String) throws -> URL {
        guard let raw, raw.hasPrefix("/"), !raw.contains("\0") else {
            throw DeterministicProfileError.invalidFixture
        }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw DeterministicProfileError.invalidFixture
        }
        _ = label
        return url
    }

    private static func containedURL(_ raw: String?, root: URL, label: String) throws -> URL {
        let candidate = try ownedURL(raw, label: label)
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw DeterministicProfileError.invalidFixture
        }
        return candidate
    }

    private static func validatedService(_ raw: String?) throws -> String {
        guard let raw,
              raw.range(of: #"^dev\.playstead\.mac\.live\.[a-z0-9-]{8,80}$"#, options: .regularExpression) != nil else {
            throw DeterministicProfileError.invalidFixture
        }
        return raw
    }
}
#endif
