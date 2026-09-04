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
        maybeRunSaveEndToEnd(environment: environment, root: root, appEnvironment: appEnvironment)
        return UITestProfileSession(fixture: nil, environment: appEnvironment)
    }

    // MARK: - Plan 04-04 task 3: the save tracer's live end-to-end proof
    //
    // `SaveEndToEndTests` (PlaysteadUITests) cannot `@testable import
    // Playstead` -- a UI test target drives the packaged app only through
    // its accessible surface, never its internal Swift types. This hook
    // is that surface: triggered by three additional env vars (an
    // artifact path to write bytes to, a content key naming the save
    // line's identity, and a result-file path), it runs the real
    // capture -> local durability -> upload lane -> live-server commit ->
    // sync-back round trip in-process using the app's own paired
    // `APIClient`/`SyncEngine`, then writes a small JSON result the
    // XCUITest polls for on disk -- mirroring the existing
    // `first-sentinel.json`/`second-sentinel.json` convention rather
    // than inventing a UI surface purely to be inspected by a test.
    static let saveArtifactPathKey = "PLAYSTEAD_UI_TEST_SAVE_ARTIFACT_PATH"
    static let saveContentKeyKey = "PLAYSTEAD_UI_TEST_SAVE_CONTENT_KEY"
    static let saveResultPathKey = "PLAYSTEAD_UI_TEST_SAVE_RESULT_PATH"

    private struct FixedArtifactSource: SaveArtifactSource {
        let data: Data
        func readArtifact() -> Data? { data }
    }

    private static func maybeRunSaveEndToEnd(
        environment: [String: String], root: URL, appEnvironment: AppEnvironment
    ) {
        guard
            let artifactRaw = environment[saveArtifactPathKey],
            let resultRaw = environment[saveResultPathKey],
            let contentKey = environment[saveContentKeyKey]
        else { return }

        // The artifact must already exist (the XCUITest writes it before
        // launch) and go through the same ownership-checked path every
        // other live-fixture path does. The result path does *not* yet
        // exist at launch time -- this process is what creates it -- so
        // it only needs root-containment, not `attributesOfItem`.
        guard
            let artifactURL = try? containedURL(artifactRaw, root: root, label: "save artifact"),
            let resultURL = try? containedDestinationURL(resultRaw, root: root)
        else { return }

        Task {
            do {
                try await runSaveEndToEnd(
                    artifactURL: artifactURL, resultURL: resultURL, contentKey: contentKey, appEnvironment: appEnvironment
                )
            } catch {
                // Best effort: the absence of the result file at
                // `resultURL` is itself the signal the polling XCUITest
                // times out on -- no separate failure channel is needed.
            }
        }
    }

    private static func runSaveEndToEnd(
        artifactURL: URL, resultURL: URL, contentKey: String, appEnvironment: AppEnvironment
    ) async throws {
        let bytes = try Data(contentsOf: artifactURL)
        let saveStore = await SaveStore(localStore: appEnvironment.localStore)
        let destinationDirectory = artifactURL.deletingLastPathComponent().appendingPathComponent("captured-saves", isDirectory: true)
        let poller = SaveCapturePoller(source: FixedArtifactSource(data: bytes), destinationDirectory: destinationDirectory)

        // Three identical reads, driven directly rather than via the 1 Hz
        // poll loop, to reach quiescence (D-03) deterministically and
        // instantly.
        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        guard let capture = try await poller.observe(bytes) else {
            throw DeterministicProfileError.stateMismatch("save-e2e: capture did not quiesce")
        }

        let line = try saveStore.resolveLine(
            contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: UUIDv7.generate()
        )

        let revisionID = UUIDv7.generate()
        try saveStore.insertRevision(SaveRevisionRow(
            id: revisionID,
            saveLineID: line.id,
            parentRevisionID: nil,
            blobSHA256: capture.sha256,
            sizeBytes: capture.sizeBytes,
            originDeviceID: nil,
            deviceCapturedAt: nil,
            recordedAt: nil,
            captureMethod: "poll",
            adapterID: "e2e-harness",
            adapterVersion: "1.0",
            saveFormat: "sram",
            formatConfidence: "exact",
            playSessionID: nil,
            durability: SaveDurability.localOnly.rawValue,
            localPath: capture.localPath
        ))

        guard let apiClient = await appEnvironment.apiClient else {
            throw DeterministicProfileError.stateMismatch("save-e2e: no paired APIClient")
        }

        let lane = SaveUploadLane(apiClient: apiClient, saveStore: saveStore)
        let drainResult = await lane.drainOnce()
        guard drainResult.sent == 1 else {
            throw DeterministicProfileError.stateMismatch("save-e2e: upload did not complete")
        }

        // Drive a fresh sync so the revision is observed coming back
        // through the exact journal/snapshot spine a second device (or
        // a clean reinstall) would use -- the tracer's whole point.
        await appEnvironment.syncEngine.syncNow()

        guard let roundTripped = saveStore.fetchRevision(id: revisionID) else {
            throw DeterministicProfileError.stateMismatch("save-e2e: revision not found after sync")
        }

        let result: [String: Any] = [
            "revision_id": revisionID,
            "blob_sha256": roundTripped.blobSHA256,
            "size_bytes": roundTripped.sizeBytes,
            "durability": roundTripped.durability,
            "captured_sha256": capture.sha256,
            "captured_size_bytes": capture.sizeBytes
        ]
        let data = try JSONSerialization.data(withJSONObject: result)
        try data.write(to: resultURL, options: .atomic)
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

    /// A root-contained path that does not need to exist yet -- for a
    /// destination this process itself will create (plan 04-04's save
    /// e2e result file), unlike `containedURL`, which requires the path
    /// to already exist with correct ownership.
    private static func containedDestinationURL(_ raw: String?, root: URL) throws -> URL {
        guard let raw, raw.hasPrefix("/"), !raw.contains("\0") else {
            throw DeterministicProfileError.stateMismatch("live fixture destination path is invalid")
        }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw DeterministicProfileError.stateMismatch("live fixture destination path escaped its run root")
        }
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
