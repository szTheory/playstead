#if UI_TESTING
import Foundation

@MainActor
final class UITestProfileSession {
    private let profileFixture: DeterministicProfileFixture?
    let environment: AppEnvironment

    /// Deterministic profile callers retain their original nonoptional API.
    /// The live-server mode has no deterministic fixture and must never ask
    /// for one; doing so is a harness programming error and fails closed.
    var fixture: DeterministicProfileFixture {
        guard let profileFixture else {
            fatalError("live-server session has no deterministic profile fixture")
        }
        return profileFixture
    }

    init(fixture: DeterministicProfileFixture?, environment: AppEnvironment) {
        self.profileFixture = fixture
        self.environment = environment
    }

    deinit {
        if let profileFixture, !profileFixture.preservesRootForRelaunch {
            try? profileFixture.cleanup()
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

        // The handoff is one-shot: consumed into the scoped Keychain and then
        // deleted. SwiftUI does not promise a single initializer call per
        // launch, so "already consumed" is a normal state rather than a
        // failure -- and it cannot be established by checking existence first,
        // because that check races the pass doing the deleting. Resolving the
        // path is itself a filesystem access that races, so it belongs inside
        // this do block too. The Keychain check below keeps it fail-closed: a
        // handoff that is gone with no stored credential is still fatal.
        var credentialWasConsumed = false
        if let rawHandoff = environment[handoffKey] {
            do {
                let handoffURL = try containedURL(rawHandoff, root: root, label: "credential handoff")
                try consumeCredentialHandoff(at: handoffURL, into: keychain)
                credentialWasConsumed = true
            } catch let error as CocoaError
                where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // Both codes mean the same thing here: another pass got there
                // first. Reading reports .fileReadNoSuchFile (260) while
                // removal reports .fileNoSuchFile (4), and the race can land on
                // either.
                credentialWasConsumed = false
            }
        }
        if !credentialWasConsumed, keychain.loadCredential() == nil {
            throw DeterministicProfileError.stateMismatch("scoped live credential is missing")
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

    /// Reads one credential handoff into the scoped Keychain and removes it.
    /// Throws a CocoaError no-such-file code when another pass already consumed it.
    @MainActor
    private static func consumeCredentialHandoff(at url: URL, into keychain: KeychainStore) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw DeterministicProfileError.stateMismatch("live credential handoff ownership or mode is invalid")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count > 0, data.count <= 4_096 else {
            throw DeterministicProfileError.stateMismatch("live credential handoff size is invalid")
        }
        let handoff = try JSONDecoder().decode(CredentialHandoff.self, from: data)
        try FileManager.default.removeItem(at: url)

        let credential = PairingCredential(
            deviceID: handoff.deviceID,
            baseURL: handoff.baseURL,
            token: handoff.credential
        )
        guard case .success = keychain.storeCredential(credential),
              keychain.loadCredential() == credential else {
            throw DeterministicProfileError.stateMismatch("live credential did not persist in scoped Keychain")
        }
    }

    private static func ownedURL(_ raw: String?, label: String) throws -> URL {
        guard let raw, raw.hasPrefix("/"), !raw.contains("\0") else {
            throw DeterministicProfileError.stateMismatch("live fixture path is invalid")
        }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw DeterministicProfileError.stateMismatch("live fixture path ownership is invalid")
        }
        _ = label
        return url
    }

    private static func containedURL(_ raw: String?, root: URL, label: String) throws -> URL {
        let candidate = try ownedURL(raw, label: label)
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw DeterministicProfileError.stateMismatch("live fixture path escaped its run root")
        }
        return candidate
    }

    private static func validatedService(_ raw: String?) throws -> String {
        guard let raw,
              raw.range(of: #"^dev\.playstead\.mac\.live\.[a-z0-9-]{8,80}$"#, options: .regularExpression) != nil else {
            throw DeterministicProfileError.stateMismatch("live Keychain service is invalid")
        }
        return raw
    }
}
#endif
