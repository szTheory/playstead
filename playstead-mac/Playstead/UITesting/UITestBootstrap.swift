#if UI_TESTING
import Foundation
import CryptoKit
import Security

@MainActor
final class UITestProfileSession {
    private let profileFixture: DeterministicProfileFixture?
    let environment: AppEnvironment
    let recoveryDirectLaunch: UITestBootstrap.RecoveryDirectLaunch?
    var isLiveServerSession: Bool { profileFixture == nil }

    /// Deterministic profile callers retain their original nonoptional API.
    /// The live-server mode has no deterministic fixture and must never ask
    /// for one; doing so is a harness programming error and fails closed.
    var fixture: DeterministicProfileFixture {
        guard let profileFixture else {
            fatalError("live-server session has no deterministic profile fixture")
        }
        return profileFixture
    }

    init(
        fixture: DeterministicProfileFixture?,
        environment: AppEnvironment,
        recoveryDirectLaunch: UITestBootstrap.RecoveryDirectLaunch? = nil
    ) {
        self.profileFixture = fixture
        self.environment = environment
        self.recoveryDirectLaunch = recoveryDirectLaunch
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
    /// Plan 04.5-01: the live-server pairing ceremony proof starts with a
    /// genuinely empty scoped Keychain and pairs it *through the real
    /// `PairingView`*, so — unlike every other live-server session — no
    /// pre-existing credential (handoff or otherwise) is required or
    /// expected.
    static let unpairedKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED"
    /// Direct recovery proof uses the existing scoped live-server bootstrap,
    /// but launches the signed app without an XCUITest runner. Both values
    /// are required together and are accepted only inside the owned root.
    static let recoveryDirectTargetKey = "PLAYSTEAD_RECOVERY_DIRECT_PAIRING_TARGET"
    static let recoveryDirectReportKey = "PLAYSTEAD_RECOVERY_DIRECT_REPORT"
    static let recoveryDirectTrustAnchorKey = "PLAYSTEAD_RECOVERY_DIRECT_TRUST_ANCHOR"
    static let recoveryDirectInteractiveKey = "PLAYSTEAD_RECOVERY_DIRECT_INTERACTIVE"
    static let liveServerLoginKeychainKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER_LOGIN_KEYCHAIN"
    static let liveServerTrustAnchorKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER"
    static let liveServerTrustAnchorDigestKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256"
    static let liveServerPairingTargetKey = "PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET"

    struct RecoveryDirectLaunch {
        let targetURL: URL
        let reportURL: URL
        let interactive: Bool
        /// DER bytes are validated from a root-owned file and remain only in
        /// process memory. This is not the durable post-pairing pin.
        let trustAnchorData: Data
    }

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
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
            biosReferences: profile.uiTestingBiosReferences,
            requiresBiosForAcceptance: profile.requiresBIOSForUITesting,
            credential: profile.uiTestingCredential
        )
        appEnvironment.blockExternalIOForUITesting()
        maybeRunSaveRestoreProof(environment: processEnvironment, root: fixture.root, appEnvironment: appEnvironment)
        maybeRunZeroNetworkPlayFlowProof(environment: processEnvironment, root: fixture.root, appEnvironment: appEnvironment)
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
        let recoveryDirectLaunch = try recoveryDirectLaunch(environment: environment, root: root)
        // A fresh unpaired profile must create its scoped Keychain in this
        // process.  A file Keychain created by a launcher is password-locked
        // when the app opens it, which turns the real pairing write into an
        // interactive password prompt.  Creating it here keeps the randomly
        // generated password in memory for this process only and never
        // touches the user's login Keychain or search list.
        let usesLoginKeychain = environment[liveServerLoginKeychainKey] == "1"
        let createdKeychain: SecKeychain? = if !usesLoginKeychain && (recoveryDirectLaunch != nil || environment[unpairedKey] == "1") {
            try createScopedKeychainIfNeeded(at: environment[keychainKey], root: root)
        } else {
            nil
        }
        let service = try validatedService(environment[keychainServiceKey])
        let allowsUnpaired = environment[unpairedKey] == "1"
        let suppliedPairingTrustAnchor = try liveServerPairingTrustAnchor(
            environment: environment, root: root, allowsUnpaired: allowsUnpaired
        )
        let keychain: KeychainStore = if usesLoginKeychain {
            // The recovery profile remains filesystem-isolated, but this
            // opt-in uses the normal macOS Keychain rather than a disposable
            // file Keychain whose memory-only password cannot be supplied to
            // an owner-facing prompt.
            KeychainStore(service: service)
        } else if let createdKeychain {
            KeychainStore.uiTestingStore(service: service, keychain: createdKeychain)
        } else {
            try KeychainStore.uiTestingStore(
                service: service,
                fileURL: containedURL(environment[keychainKey], root: root, label: "Keychain")
            )
        }

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
        if !credentialWasConsumed, keychain.loadCredential() == nil, !allowsUnpaired {
            throw DeterministicProfileError.stateMismatch("scoped live credential is missing")
        }

        let paths = AppPaths(root: root)
        let localStore = try LocalStore(paths: paths)
        if !allowsUnpaired, let suppliedPairingTrustAnchor {
            // Snapshot and save proofs begin with an already-provisioned
            // credential rather than running the pairing UI. Seed the exact
            // run-owned anchor into that test profile's normal durable pin
            // location, reproducing the post-pairing state the API client
            // expects without touching System Keychain trust.
            let capture = PinnedCertificateCapture(capturedCertificateData: suppliedPairingTrustAnchor)
            guard capture.writeCapturedCertificate(to: paths.pinnedCertificate) else {
                throw DeterministicProfileError.stateMismatch("live server profile pin could not be persisted")
            }
        }
        let appEnvironment = AppEnvironment(
            paths: paths,
            apiClient: APIClient(keychain: keychain, pinnedCertificateURL: paths.pinnedCertificate),
            reachability: Reachability(startOnline: true, monitorAutomatically: false),
            // The pairing ceremony must write into the same scoped
            // Keychain `apiClient` reads its credential from -- never the
            // production default, which would be the real login Keychain.
            pairingKeychain: keychain,
            pairingTrustAnchorData: suppliedPairingTrustAnchor
        )
        maybeRunSaveEndToEnd(environment: environment, root: root, appEnvironment: appEnvironment)
        return UITestProfileSession(
            fixture: nil,
            environment: appEnvironment,
            recoveryDirectLaunch: recoveryDirectLaunch
        )
    }

    /// The LiveServer ceremony may use only the CA issued beneath its exact
    /// run-owned service root, and only for the fixed loopback HTTPS fixture.
    /// Absence is allowed for other LiveServer tests; a partial or invalid
    /// supplied capability is rejected before the pairing UI can issue a request.
    private static func liveServerPairingTrustAnchor(
        environment: [String: String], root: URL, allowsUnpaired: Bool
    ) throws -> Data? {
        let rawAnchor = environment[liveServerTrustAnchorKey]
        let expectedDigestValue = environment[liveServerTrustAnchorDigestKey]
        let target = environment[liveServerPairingTargetKey]
        guard rawAnchor != nil || expectedDigestValue != nil || target != nil else {
            if allowsUnpaired {
                throw DeterministicProfileError.stateMismatch("live pairing trust anchor is missing")
            }
            return nil
        }
        guard let raw = rawAnchor,
              let expectedDigest = expectedDigestValue?.lowercased(),
              expectedDigest.count == 64,
              expectedDigest.allSatisfy({ $0.isHexDigit }) else {
            throw DeterministicProfileError.stateMismatch("live pairing trust anchor is missing")
        }
        guard environment[liveServerKey] == "1",
              target == "https://127.0.0.1:4010",
              environment[recoveryDirectTargetKey] == nil,
              environment[recoveryDirectReportKey] == nil,
              environment[recoveryDirectTrustAnchorKey] == nil else {
            throw DeterministicProfileError.stateMismatch("live pairing trust anchor mode is invalid")
        }
        let url = try containedURL(raw, root: root, label: "live pairing trust anchor")
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (values[.type] as? FileAttributeType) == .typeRegular,
              let size = (values[.size] as? NSNumber)?.intValue,
              size > 0, size <= 16_384 else {
            throw DeterministicProfileError.stateMismatch("live pairing trust anchor file is invalid")
        }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard bytes.count == size,
              let certificate = PinnedCertificateCapture.certificateData(fromRecoveryFile: bytes),
              let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
              Data(SHA256.hash(data: certificate)).map({ String(format: "%02x", $0) }).joined() == expectedDigest else {
            throw DeterministicProfileError.stateMismatch("live pairing trust anchor is invalid")
        }
        if #available(macOS 15.0, *) {
            guard let before = SecCertificateCopyNotValidBeforeDate(parsed) as Date?,
                  let after = SecCertificateCopyNotValidAfterDate(parsed) as Date?,
                  before <= Date(), after > Date() else {
                throw DeterministicProfileError.stateMismatch("live pairing trust anchor is expired or not yet valid")
            }
        }
        return certificate
    }

    /// Parses the direct-app recovery seam as a capability pair. A target
    /// without a report could silently make a network request, and a report
    /// without a target could be forged, so either partial configuration is
    /// refused before the app constructs any product state beyond the already
    /// isolated live-server session.
    private static func recoveryDirectLaunch(
        environment: [String: String], root: URL
    ) throws -> RecoveryDirectLaunch? {
        let rawTarget = environment[recoveryDirectTargetKey]
        let rawReport = environment[recoveryDirectReportKey]
        let rawTrustAnchor = environment[recoveryDirectTrustAnchorKey]
        guard rawTarget != nil || rawReport != nil || rawTrustAnchor != nil else { return nil }
        guard
            let rawTarget,
            let rawReport,
            let rawTrustAnchor,
            let targetURL = URL(string: rawTarget),
            targetURL.scheme?.lowercased() == "https",
            targetURL.host != nil,
            targetURL.user == nil,
            targetURL.password == nil
        else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch configuration is invalid")
        }
        let trustAnchorURL = try containedURL(rawTrustAnchor, root: root, label: "recovery trust anchor")
        let rawTrustAnchorData = try Data(contentsOf: trustAnchorURL, options: [.mappedIfSafe])
        guard rawTrustAnchorData.count > 0, rawTrustAnchorData.count <= 16_384,
              let trustAnchorData = PinnedCertificateCapture.certificateData(fromRecoveryFile: rawTrustAnchorData)
        else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch trust anchor is invalid")
        }
        return RecoveryDirectLaunch(
            targetURL: targetURL,
            reportURL: try containedDestinationURL(rawReport, root: root),
            interactive: environment[recoveryDirectInteractiveKey] == "1",
            trustAnchorData: trustAnchorData
        )
    }

    /// Creates only a fresh run-owned Keychain. `SecKeychainCreate` receives
    /// an explicit destination and does not add it to the user's search list;
    /// every subsequent query is scoped by `KeychainStore.uiTestingStore`.
    /// The randomly generated password is memory-only and never logged or
    /// persisted, so the creating process can write without a password prompt.
    private static func createScopedKeychainIfNeeded(at raw: String?, root: URL) throws -> SecKeychain? {
        guard let raw else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch is missing a Keychain")
        }
        // Both the direct-recovery driver and macOS may spell the same
        // temporary directory differently (`/private/tmp` versus its resolved
        // target). Compare canonical filesystem locations, not URL spelling;
        // this still rejects a child that resolves outside the owned root.
        let keychainURL = canonicalFileURL(raw)
        guard keychainURL.path.hasPrefix(root.path + "/") else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch Keychain escaped its run root")
        }
        if FileManager.default.fileExists(atPath: keychainURL.path) { return nil }

        var password = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, password.count, &password) == errSecSuccess else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch Keychain password generation failed")
        }
        var created: SecKeychain?
        let status = keychainURL.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
            }
        }
        guard status == errSecSuccess, let created else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch Keychain creation failed")
        }

        let unlockStatus = password.withUnsafeBytes { bytes in
            SecKeychainUnlock(created, UInt32(password.count), bytes.baseAddress, true)
        }
        guard unlockStatus == errSecSuccess else {
            throw DeterministicProfileError.stateMismatch("recovery direct launch Keychain unlock failed")
        }
        return created
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
    private static let saveReliabilityEnabledKey = "PLAYSTEAD_UI_TEST_SAVE_RELIABILITY"
    private static let saveTransientTokenKey = "PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_TOKEN"
    private static let saveTransientRevisionIDKey = "PLAYSTEAD_UI_TEST_SAVE_TRANSIENT_REVISION_ID"
    private static let saveConflictTokenKey = "PLAYSTEAD_UI_TEST_SAVE_CONFLICT_TOKEN"
    private static let saveControlRootKey = "PLAYSTEAD_UI_TEST_SAVE_CONTROL_ROOT"
    private static let saveEndToEndClaimDirectory = ".save-e2e-execution-claim"

    private struct SaveReliabilityControl {
        let transientToken: String
        let transientRevisionID: String
        let conflictToken: String
        let controlRoot: URL

        init?(environment: [String: String]) {
            guard environment[UITestBootstrap.saveReliabilityEnabledKey] == "1",
                  let transientToken = environment[UITestBootstrap.saveTransientTokenKey],
                  let transientRevisionID = environment[UITestBootstrap.saveTransientRevisionIDKey],
                  let conflictToken = environment[UITestBootstrap.saveConflictTokenKey],
                  let serverRoot = environment["PLAYSTEAD_MAC_CI_ROOT"],
                  let controlRootRaw = environment[UITestBootstrap.saveControlRootKey],
                  UUID(uuidString: transientToken) != nil,
                  UUID(uuidString: transientRevisionID) != nil,
                  UUID(uuidString: conflictToken) != nil else { return nil }

            let expectedControlRoot = URL(fileURLWithPath: serverRoot, isDirectory: true)
                .appendingPathComponent("mac-client-control", isDirectory: true)
                .standardizedFileURL
            let suppliedControlRoot = URL(fileURLWithPath: controlRootRaw, isDirectory: true)
                .standardizedFileURL
            guard expectedControlRoot == suppliedControlRoot,
                  FileManager.default.fileExists(atPath: expectedControlRoot.path) else { return nil }

            self.transientToken = transientToken.lowercased()
            self.transientRevisionID = transientRevisionID.lowercased()
            self.conflictToken = conflictToken.lowercased()
            self.controlRoot = expectedControlRoot
        }

        func directory(for token: String) -> URL {
            controlRoot.appendingPathComponent("save-e2e-\(token)", isDirectory: true)
        }
    }

    private struct SaveConflictObservation: Sendable {
        let status: Int
        let code: String
        let classification: SaveUploadFailureClassification
        let cause: SaveUploadFailureCause
        let correlationID: String?
        let escalates: Bool
    }

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

        // SwiftUI may reconstruct the root view and evaluate State's
        // initial value more than once. A save proof has external effects
        // (server requests and result files), so only one bootstrap may own
        // it for a profile root, even if reconstruction crosses processes.
        guard claimSaveEndToEndExecution(root: root, resultURL: resultURL) else { return }

        let reliabilityControl: SaveReliabilityControl?
        if environment[saveReliabilityEnabledKey] == "1" {
            guard let control = SaveReliabilityControl(environment: environment) else {
                try? Data("save-e2e: reliability control invalid".utf8)
                    .write(to: saveEndToEndErrorURL(for: resultURL), options: .atomic)
                return
            }
            reliabilityControl = control
        } else {
            reliabilityControl = nil
        }

        Task {
            do {
                try await runSaveEndToEnd(
                    artifactURL: artifactURL, resultURL: resultURL, contentKey: contentKey,
                    appEnvironment: appEnvironment, reliabilityControl: reliabilityControl
                )
            } catch {
                // The absence of the result file IS a signal the polling
                // XCUITest times out on -- but it is a signal with no
                // content: every failure looks like "never written
                // within 60s", so a genuinely slow run and a broken
                // upload are indistinguishable. Hosted run 34281587417
                // failed exactly this way and said nothing about why.
                //
                // Same discipline as the live-server fixture's own
                // diagnostic (`live-server.sh`): name the stage, and
                // never emit anything a sanitizer would have to strip.
                // `DeterministicProfileError.stateMismatch` reasons are
                // fixed literals written in this file; any other error
                // is reported by type alone, because an arbitrary
                // error's description can carry paths.
                let reason: String
                if case let DeterministicProfileError.stateMismatch(literal) = error {
                    reason = literal
                } else {
                    reason = "save-e2e: unexpected \(type(of: error))"
                }
                try? Data(reason.utf8).write(to: saveEndToEndErrorURL(for: resultURL), options: [.atomic])
            }
        }
    }

    private static func claimSaveEndToEndExecution(root: URL, resultURL: URL) -> Bool {
        let claim = root.appendingPathComponent(saveEndToEndClaimDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: claim,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return true
        } catch {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: claim.path, isDirectory: &isDirectory), isDirectory.boolValue {
                // A sibling SwiftUI bootstrap already claimed this run.
                return false
            }
            try? Data("save-e2e: execution claim unavailable".utf8)
                .write(to: saveEndToEndErrorURL(for: resultURL), options: .atomic)
            return false
        }
    }

    /// The sibling file the harness writes its failure reason to. A
    /// sibling of an already-contained destination is contained by the
    /// same check, so this needs no second validation pass.
    /// Bounded so a genuinely broken upload still fails, and fails fast.
    /// A healthy server needs one attempt; one transient error needs two.
    private static let saveEndToEndMaxUploadAttempts = 3

    /// Whether the lane's latest verdict is one this harness should keep
    /// retrying, in the ONLY vocabulary this repo owns for that question.
    ///
    /// `== .none` is not that question, and reading it as if it were is the
    /// defect run 34670123715 caught at `save-e2e-harness=upload-server-refused`.
    /// `SaveUploadFailureClassification` has seven cases, and its own doc
    /// states that three of them -- `.none`, `.offlineQueue`, `.slowUpload` --
    /// "are the product working correctly and must never escalate". Only
    /// D-40's four unfixable reasons are a refusal.
    ///
    /// `.offlineQueue` is not a corner case here, it is the expected state:
    /// the app drains on the reachability transition at pairing time, when
    /// the server may not be reachable yet. Treating that as "your server
    /// has refused this Mac" both skipped the retry and named the wrong
    /// cause.
    ///
    /// This asks via `OnlyCopyEscalationReason(classification:)` rather than
    /// listing cases again, because that initializer is the same gate the
    /// shipped escalation panel uses. A new classification therefore cannot
    /// drift between the product and this harness: whatever the panel would
    /// escalate is exactly what this refuses to retry.
    private static func isRetryable(_ classification: SaveUploadFailureClassification) -> Bool {
        OnlyCopyEscalationReason(classification: classification) == nil
    }

    static func saveEndToEndErrorURL(for resultURL: URL) -> URL {
        resultURL.deletingPathExtension().appendingPathExtension("error.txt")
    }

    private static func runSaveEndToEnd(
        artifactURL: URL, resultURL: URL, contentKey: String, appEnvironment: AppEnvironment,
        reliabilityControl: SaveReliabilityControl?
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

        let revisionID = reliabilityControl?.transientRevisionID ?? UUIDv7.generate()
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

        // Still asserted: an unpaired app would fail the upload for a reason
        // that has nothing to do with what this test proves. The client
        // itself is no longer needed here, since the lane below is the app's
        // own and already holds it.
        guard await appEnvironment.apiClient != nil else {
            throw DeterministicProfileError.stateMismatch("save-e2e: no paired APIClient")
        }

        // The APP'S OWN lane, never a second one built here.
        //
        // The running app also drains save uploads on a reachability
        // transition (PlaysteadApp.swift: `Task { await uploadLane.drainOnce() }`
        // inside `reachability.onChange`), which in CI fires right after
        // pairing -- exactly when this harness is inserting its revision.
        // Actors are reentrant at `await`, so merely sharing an actor did not
        // prevent both passes from sending this revision at once. The lane's
        // per-revision in-flight gate now makes overlapping callers await the
        // same upload outcome; the focused lane regression test pins it.
        //
        // The harness still uses the same lane as production, including its
        // ordinary retry and idempotency behavior.
        let lane = appEnvironment.saveUploadLane

        // Drive the lane the way PRODUCTION does, not the way a single pass
        // does. `drainOnce` is ONE attempt by a component whose entire job
        // is retrying: any single error inside it schedules a backoff and
        // returns `sent == 0`. Asserting first-attempt success asserted
        // something this product never promises, and that -- not the server,
        // and not a timeout -- is what made SaveEndToEndTests flaky in runs
        // 34648546919 and 34658266643. The mechanism is pinned in
        // SaveUploadLaneTests
        // .test_oneTransientFailure_makesASinglePassSendNothing_thoughTheNextPassSucceeds,
        // which reproduces it in under a second.
        //
        // Only the RETRYABLE case loops. A server that refused for one of
        // D-40's unfixable reasons, or a pending set that never contained
        // this revision, still fails on the first pass: retrying those would
        // be the "green by persistence" that hides the defect class e6316d5
        // caught, where uploads 404'd against every real server.
        //
        // `at:` advances past the lane's own backoff instead of sleeping, so
        // this costs no wall-clock: the backoff schedule has its own tests
        // and is not what this check is about.
        var transientEvidence: [String: Any]?
        var drainResult = await lane.drainOnce()
        if let reliabilityControl {
            let marker = reliabilityControl.directory(for: reliabilityControl.transientToken)
                .appendingPathComponent("transient-consumed")
            let consumedToken = try? String(contentsOf: marker, encoding: .utf8)
            guard consumedToken == reliabilityControl.transientToken else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient server hook was not observed")
            }

            guard let failure = await lane.transientFailureEvidence() else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient lane evidence missing")
            }
            guard failure.classification == .none else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient classification was not none")
            }
            guard failure.cause == .http5xx else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient cause was not http5xx")
            }
            guard let status = failure.status, status == 503 else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient status was not 503")
            }
            guard let problemCode = failure.problemCode, problemCode == .serviceUnavailable else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient problem code was not service unavailable")
            }
            guard OnlyCopyEscalationReason(classification: failure.classification) == nil else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient response escalated")
            }
            guard let correlationID = failure.correlationID,
                  UUID(uuidString: correlationID) != nil else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient correlation identity missing")
            }
            transientEvidence = [
                "http_status": status,
                "problem_code": problemCode.rawValue,
                "failure_classification": "none",
                "failure_cause": "http5xx",
                "escalates": false,
                "correlation_id": correlationID
            ]

            // A reachability-triggered app drain may have consumed the 503
            // before this harness's explicit call. The lane's failure cells
            // above are authoritative; advance past its ordinary backoff
            // once so this exact round trip still proves the production retry.
            drainResult = await lane.drainOnce(at: Date().addingTimeInterval(3600))
        }
        var attempt = reliabilityControl == nil ? 1 : 2
        while drainResult.sent == 0,
              drainResult.stoppedForRetry,
              Self.isRetryable(drainResult.failureClassification),
              attempt < Self.saveEndToEndMaxUploadAttempts {
            attempt += 1
            drainResult = await lane.drainOnce(at: Date().addingTimeInterval(Double(attempt) * 3600))
        }

        // Assert the OUTCOME, not this lane's counter. The claim under test
        // is "one save round trips capture -> upload -> journal -> sync", not
        // "the lane object I happen to hold incremented `sent`". With the
        // app's own lane also draining, `sent` belongs to whichever pass did
        // the work, while the revision's durability is the fact either way.
        let uploaded = saveStore.fetchRevision(id: revisionID)?.durability == SaveDurability.uploaded.rawValue

        if !uploaded, drainResult.stoppedForRetry, Self.isRetryable(drainResult.failureClassification) {
            // Retryable, and still failing after every attempt. That is no
            // longer a blip -- it is a server that is genuinely not
            // accepting this upload.
            switch drainResult.saveUploadFailureCause {
            case .none, .localState:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted local retries")
            case .notPaired:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted retries without pairing")
            case .transportConnectivity:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted connectivity retries")
            case .transportTimeout:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted timeout retries")
            case .transportTLS:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted TLS retries")
            case .transportOther:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted other transport retries")
            case .invalidResponse:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted invalid-response retries")
            case .http408:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted HTTP 408 retries")
            case .http429:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted HTTP 429 retries")
            case .http5xx:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted HTTP 5xx retries")
            case .http400, .http401, .http403, .http404, .http409, .http413, .http422,
                 .idempotencyConflict, .serverNotFound:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted nonretryable HTTP status")
            case .httpOther:
                throw DeterministicProfileError.stateMismatch("save-e2e: upload exhausted other HTTP retries")
            }
        }

        guard uploaded else {
            // `drainOnce` is ONE pass over a lane whose whole job is to
            // retry: any single error inside it sets `stoppedForRetry`,
            // schedules a backoff, and returns with `sent == 0`. So a
            // failure here means one of three quite different things, and
            // reporting them all as "upload did not complete" is what made
            // this an opaque flake -- both `stoppedForRetry` and the
            // classification were already sitting here unread.
            //
            // The classification comes off `drainResult`, NOT off the
            // lane. `lane.lastFailureClassification` is a nonisolated read
            // of one last-writer-wins cell, and WINDOWS #67's own fix made
            // this harness share the app's lane -- which drains on the
            // reachability transition at pairing time. So the cell could
            // hold the app pass's classification while `stoppedForRetry`
            // described this pass's, and an ordinary `.offlineQueue` stop
            // was reported as "server refused" (WINDOWS #87).
            //
            // These stay FIXED LITERALS, per this file's rule: a `Bool` and
            // a closed enum this repo owns are safe to branch on, but an
            // error's own description can carry paths and must never reach
            // the reason channel. That rule is also why the refusal splits
            // by case rather than interpolating: naming which of D-40's
            // four reasons refused makes the next occurrence diagnosable in
            // one run, and each is a fixed literal this repo owns.
            if drainResult.stoppedForRetry {
                guard let refusal = OnlyCopyEscalationReason(classification: drainResult.failureClassification) else {
                    // Retryable by design: transport loss, 5xx, rate
                    // limiting. Production would simply try again.
                    throw DeterministicProfileError.stateMismatch("save-e2e: upload stopped for retry, retryable")
                }
                // One of D-40's genuinely unfixable server reasons. This
                // is a real defect, never a flake.
                switch refusal {
                case .revokedAuth:
                    throw DeterministicProfileError.stateMismatch("save-e2e: upload refused, revoked auth")
                case .capabilitySkew:
                    throw DeterministicProfileError.stateMismatch("save-e2e: upload refused, capability skew")
                case .serverRefusal:
                    switch drainResult.saveUploadFailureCause {
                    case .http400:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 400")
                    case .http401:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 401")
                    case .http403:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 403")
                    case .http404:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 404")
                    case .http409:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 409")
                    case .http413:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 413")
                    case .http422:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused with HTTP 422")
                    case .idempotencyConflict:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused idempotency conflict")
                    case .serverNotFound:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused not found")
                    default:
                        throw DeterministicProfileError.stateMismatch("save-e2e: upload refused, server refusal")
                    }
                case .compatibilityRejection:
                    throw DeterministicProfileError.stateMismatch("save-e2e: upload refused, compatibility rejection")
                }
            }
            // Not stopped, yet nothing sent: the pending set was empty, so
            // the revision this harness just inserted was not visible to
            // the lane at all. Also a real defect.
            throw DeterministicProfileError.stateMismatch("save-e2e: upload found nothing pending")
        }

        // Drive a fresh sync so the revision is observed coming back
        // through the exact journal/snapshot spine a second device (or
        // a clean reinstall) would use -- the tracer's whole point.
        await appEnvironment.syncEngine.syncNow()

        guard let roundTripped = saveStore.fetchRevision(id: revisionID) else {
            throw DeterministicProfileError.stateMismatch("save-e2e: revision not found after sync")
        }

        var reliabilityEvidence: [String: Any]?
        if let reliabilityControl {
            guard let transientEvidence else {
                throw DeterministicProfileError.stateMismatch("save-e2e: transient response evidence missing")
            }
            let conflictEvidence = try await runSaveConflictReliability(
                bytes: bytes,
                capture: capture,
                saveStore: saveStore,
                apiClient: try await requireAPIClient(appEnvironment),
                control: reliabilityControl
            )
            reliabilityEvidence = ["transient": transientEvidence, "conflict": conflictEvidence]
        }

        var result: [String: Any] = [
            "revision_id": revisionID,
            "blob_sha256": roundTripped.blobSHA256,
            "size_bytes": roundTripped.sizeBytes,
            "durability": roundTripped.durability,
            "captured_sha256": capture.sha256,
            "captured_size_bytes": capture.sizeBytes,
            // WINDOWS #57 claimed `SaveUploadLane` forwards adapter
            // provenance "when present" -- reported here so the live
            // server proof asserts the claim instead of restating it.
            // This value comes back off the round-tripped revision, so
            // it is what upload -> journal -> sync actually preserved,
            // never the literal this harness inserted.
            "adapter_id": roundTripped.adapterID ?? "",
            "adapter_version": roundTripped.adapterVersion ?? ""
        ]
        if let reliabilityEvidence { result["reliability"] = reliabilityEvidence }
        let data = try JSONSerialization.data(withJSONObject: result)
        try data.write(to: resultURL, options: .atomic)
    }

    private static func requireAPIClient(_ appEnvironment: AppEnvironment) async throws -> APIClient {
        guard let apiClient = await appEnvironment.apiClient else {
            throw DeterministicProfileError.stateMismatch("save-e2e: no paired APIClient")
        }
        return apiClient
    }

    private static func runSaveConflictReliability(
        bytes: Data,
        capture: CapturedSave,
        saveStore: SaveStore,
        apiClient: APIClient,
        control: SaveReliabilityControl
    ) async throws -> [String: Any] {
        let token = control.conflictToken
        let directory = control.directory(for: token)
        guard let owner = try? String(contentsOf: directory.appendingPathComponent("owner"), encoding: .utf8),
              owner == token else {
            throw DeterministicProfileError.stateMismatch("save-e2e: conflict control identity invalid")
        }

        let contentKey = String(repeating: "f", count: 64)
        let line = try saveStore.resolveLine(
            contentKey: contentKey, saveKind: "battery", slot: "1", placeholderID: UUIDv7.generate()
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
        guard let commandID = try saveStore.ensureUploadCommandID(
            revisionID: revisionID, proposed: UUIDv7.generate()
        ) else {
            throw DeterministicProfileError.stateMismatch("save-e2e: conflict command missing")
        }

        let digestHeader = Self.saveReprDigestHeader(for: bytes)
        _ = try await apiClient.send(
            method: "PUT",
            path: "/api/v1/saves/uploads/\(commandID)",
            body: bytes,
            headers: ["Repr-Digest": digestHeader, "Content-Length": String(bytes.count)],
            contentType: "application/octet-stream"
        )

        let payload = try saveRevisionPayload(
            revisionID: revisionID,
            commandID: commandID,
            contentKey: contentKey,
            slot: "1"
        )
        let idempotencyKey = "save-revision-\(revisionID)"
        let originalTask = Task { () throws -> Int in
            try await apiClient.send(
                method: "POST",
                path: "/api/v1/saves/revisions",
                body: payload,
                headers: [
                    "Idempotency-Key": idempotencyKey,
                    "X-Playstead-Test-Hold": token
                ]
            ).status
        }

        do {
            try await Self.waitForReliabilityMarker("hold-arrived", token: token, in: directory, timeout: 10)
        } catch {
            Self.writeReliabilityMarker("release", token: token, in: directory)
            _ = await originalTask.result
            throw DeterministicProfileError.stateMismatch("save-e2e: conflict hold was not reached")
        }

        let duplicateTask = Task { () -> SaveConflictObservation in
            do {
                let response = try await apiClient.send(
                    method: "POST",
                    path: "/api/v1/saves/revisions",
                    body: payload,
                    headers: [
                        "Idempotency-Key": idempotencyKey,
                        "X-Playstead-Test-Duplicate": token
                    ]
                )
                return SaveConflictObservation(
                    status: response.status, code: "unexpected_success", classification: .none,
                    cause: .none, correlationID: nil, escalates: false
                )
            } catch let error as APIClientError {
                let problem = SaveUploadProblemEvidence(error: error)
                return SaveConflictObservation(
                    status: problem?.status ?? 0,
                    code: problem?.code.rawValue ?? "other",
                    classification: SaveUploadLane.classify(error),
                    cause: SaveUploadFailureCause.classify(error),
                    correlationID: SaveUploadLane.diagnosticEvidence(for: error)?.correlationID,
                    escalates: OnlyCopyEscalationReason(
                        classification: SaveUploadLane.classify(error)
                    ) != nil
                )
            } catch {
                return SaveConflictObservation(
                    status: 0, code: "other", classification: .none, cause: .localState,
                    correlationID: nil, escalates: false
                )
            }
        }

        do {
            try await Self.waitForReliabilityMarker("duplicate-ready", token: token, in: directory, timeout: 10)
        } catch {
            Self.writeReliabilityMarker("release", token: token, in: directory)
            _ = await originalTask.result
            _ = await duplicateTask.value
            throw DeterministicProfileError.stateMismatch("save-e2e: duplicate did not reach idempotency preflight")
        }

        Self.writeReliabilityMarker("release", token: token, in: directory)
        let originalStatus = try await originalTask.value
        let duplicate = await duplicateTask.value
        guard originalStatus == 201,
              duplicate.status == 409,
              duplicate.code == SaveUploadProblemCode.idempotencyKeyConflict.rawValue,
              duplicate.classification == .serverRefusal,
              duplicate.cause == .idempotencyConflict,
              duplicate.escalates,
              let correlationID = duplicate.correlationID,
              UUID(uuidString: correlationID) != nil else {
            throw DeterministicProfileError.stateMismatch("save-e2e: duplicate conflict was not preserved")
        }

        return [
            "original_http_status": originalStatus,
            "duplicate_http_status": duplicate.status,
            "problem_code": duplicate.code,
            "failure_classification": "serverRefusal",
            "failure_cause": "idempotencyConflict",
            "escalates": true,
            "correlation_id": correlationID
        ]
    }

    private static func saveRevisionPayload(
        revisionID: String, commandID: String, contentKey: String, slot: String
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": revisionID,
            "command_id": commandID,
            "content_key": contentKey,
            "save_kind": "battery",
            "slot": slot,
            "capture_method": "poll",
            "adapter_id": "e2e-harness",
            "adapter_version": "1.0",
            "save_format": "sram",
            "format_confidence": "exact"
        ])
    }

    private static func saveReprDigestHeader(for data: Data) -> String {
        let raw = Data(SHA256.hash(data: data))
        return "sha-256=:\(raw.base64EncodedString()):"
    }

    private static func waitForReliabilityMarker(
        _ name: String, token: String, in directory: URL, timeout: TimeInterval
    ) async throws {
        let marker = directory.appendingPathComponent(name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = try? String(contentsOf: marker, encoding: .utf8), value == token { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw DeterministicProfileError.stateMismatch("save-e2e: reliability marker timeout")
    }

    private static func writeReliabilityMarker(_ name: String, token: String, in directory: URL) {
        let marker = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try? Data(token.utf8).write(to: marker, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }

    // MARK: - Plan 04-13 task 1: the named restore proof
    //
    // `SaveRestoreProofTests` (PlaysteadUITests) proves the file half of
    // SAVE-03 -- a captured revision restores to byte-identical bytes on
    // disk -- without a live server, exactly like the deterministic
    // (non-live-server) profile branch above. This hook writes a
    // 32,768-byte artifact's revision through the same capture pipeline
    // `maybeRunSaveEndToEnd` uses, clears the restore target to simulate
    // a clean save directory, then drives the *actual* `SavePlanExecutor`
    // -- the type the launch path calls -- to restore it, and reports
    // both digests so the XCUITest can assert byte-identical equality
    // without ever inspecting internal Swift types directly (D-68).
    static let saveRestoreArtifactPathKey = "PLAYSTEAD_UI_TEST_SAVE_RESTORE_ARTIFACT_PATH"
    static let saveRestoreTargetPathKey = "PLAYSTEAD_UI_TEST_SAVE_RESTORE_TARGET_PATH"
    static let saveRestoreResultPathKey = "PLAYSTEAD_UI_TEST_SAVE_RESTORE_RESULT_PATH"

    /// A `SavePlanExecutorEnvironment` backed by the real bytes this
    /// process just captured -- not a CAS/network lookup, because the
    /// bytes for the one digest under test are already known locally.
    /// The `.fastForward` plan this hook drives never calls
    /// `captureExistingFile`/`quarantineCorruptRevision` on the happy
    /// path exercised here, so both are inert rather than fabricated.
    private struct KnownDigestEnvironment: SavePlanExecutorEnvironment {
        let bytesByDigest: [String: Data]
        func revisionBytes(forDigest digest: String) throws -> Data {
            guard let data = bytesByDigest[digest] else {
                throw SavePlanExecutorError.digestMismatch(expected: digest, actual: "missing")
            }
            return data
        }
        func captureExistingFile(at targetURL: URL) throws {}
        func quarantineCorruptRevision(digest: String, actualDigest: String) {}
    }

    /// A path that must be absolute, owned by the current user (if it
    /// already exists), and contain no NUL byte -- the same ownership bar
    /// `ownedURL` enforces, but without also requiring containment inside
    /// a specific fixture root. `maybeRunSaveRestoreProof`/
    /// `maybeRunZeroNetworkPlayFlowProof` run against the deterministic
    /// (non-live-server) profile, whose own fixture root is a private
    /// implementation detail the driving XCUITest cannot discover — unlike
    /// the live-server credential handoff above, these hooks touch no
    /// credential and gain nothing from binding to that root.
    private static func lenientDestinationURL(_ raw: String?) throws -> URL {
        guard let raw, raw.hasPrefix("/"), !raw.contains("\0") else {
            throw DeterministicProfileError.stateMismatch("test-hook path is invalid")
        }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw DeterministicProfileError.stateMismatch("test-hook path ownership is invalid")
            }
        }
        return url
    }

    private static func maybeRunSaveRestoreProof(
        environment: [String: String], root: URL, appEnvironment: AppEnvironment
    ) {
        guard
            let artifactRaw = environment[saveRestoreArtifactPathKey],
            let targetRaw = environment[saveRestoreTargetPathKey],
            let resultRaw = environment[saveRestoreResultPathKey]
        else { return }

        guard
            let artifactURL = try? lenientDestinationURL(artifactRaw),
            let targetURL = try? lenientDestinationURL(targetRaw),
            let resultURL = try? lenientDestinationURL(resultRaw)
        else { return }

        Task {
            do {
                try await runSaveRestoreProof(artifactURL: artifactURL, targetURL: targetURL, resultURL: resultURL, appEnvironment: appEnvironment)
            } catch {
                // Best effort, mirroring `maybeRunSaveEndToEnd`: the
                // absence of the result file is itself the signal the
                // polling XCUITest times out on.
            }
        }
    }

    private static func runSaveRestoreProof(
        artifactURL: URL, targetURL: URL, resultURL: URL, appEnvironment: AppEnvironment
    ) async throws {
        let bytes = try Data(contentsOf: artifactURL)
        let destinationDirectory = artifactURL.deletingLastPathComponent()
            .appendingPathComponent("restore-proof-captures", isDirectory: true)
        let poller = SaveCapturePoller(source: FixedArtifactSource(data: bytes), destinationDirectory: destinationDirectory)

        // Three identical reads to reach quiescence (D-03) deterministically,
        // exactly as `runSaveEndToEnd` does above.
        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        guard let capture = try await poller.observe(bytes) else {
            throw DeterministicProfileError.stateMismatch("save-restore-proof: capture did not quiesce")
        }

        // Simulate a clean Mac: the restore target must not exist before
        // the launch-path restore runs.
        try? FileManager.default.removeItem(at: targetURL)

        let capturedBytes = try Data(contentsOf: URL(fileURLWithPath: capture.localPath))
        let restoreEnvironment = KnownDigestEnvironment(bytesByDigest: [capture.sha256: capturedBytes])
        let executor = SavePlanExecutor(environment: restoreEnvironment)
        // `.fastForward` is the launch path's silent, no-prompt restore
        // (D-47) -- the exact case CP7-SAVE-C's step 3 ("no prompt")
        // exercises against a real emulator.
        try executor.execute(.fastForward(revisionDigest: capture.sha256), targetURL: targetURL)

        let restoredBytes = try Data(contentsOf: targetURL)
        let restoredDigest = sha256Hex(of: restoredBytes)

        let result: [String: Any] = [
            "captured_sha256": capture.sha256,
            "captured_size_bytes": capture.sizeBytes,
            "restored_sha256": restoredDigest,
            "restored_size_bytes": restoredBytes.count,
            "bytes_equal": restoredBytes == bytes
        ]
        let data = try JSONSerialization.data(withJSONObject: result)
        try data.write(to: resultURL, options: .atomic)
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Plan 04-13 task 1: the strict zero-network Play flow assertion
    //
    // Drives the same sequence `GameRowView.play()` drives -- readiness,
    // materialize, save-plan execution, and adapter spawn -- directly
    // against the assembled `AppEnvironment`, exactly as `AdapterWiringTests`
    // proves the install/verify/launch chain is reachable from the
    // assembled app rather than merely constructible in isolation.
    // `RecordingURLProtocol` is armed for the whole span so any HTTP
    // request attempted anywhere in-process -- including a detached or
    // fire-and-forget task -- is caught, not only ones issued through the
    // app's own `APIClient` session.
    static let zeroNetworkResultPathKey = "PLAYSTEAD_UI_TEST_ZERO_NETWORK_PLAY_FLOW_RESULT_PATH"

    private static func maybeRunZeroNetworkPlayFlowProof(
        environment: [String: String], root: URL, appEnvironment: AppEnvironment
    ) {
        guard
            let resultRaw = environment[zeroNetworkResultPathKey],
            let resultURL = try? lenientDestinationURL(resultRaw)
        else { return }

        Task {
            var requestCount = -1
            var failureReason: String?
            RecordingURLProtocol.armRecording()
            do {
                try await runZeroNetworkPlayFlow(root: root, appEnvironment: appEnvironment)
            } catch {
                failureReason = String(describing: error)
            }
            requestCount = RecordingURLProtocol.recordedRequestCount
            RecordingURLProtocol.disarmRecording()

            var result: [String: Any] = ["recorded_request_count": requestCount]
            if let failureReason { result["failure_reason"] = failureReason }
            if let data = try? JSONSerialization.data(withJSONObject: result) {
                try? data.write(to: resultURL, options: .atomic)
            }
        }
    }

    /// Places a real, runnable stand-in executable at the pin's declared
    /// path -- no emulator is available in this environment, so `/bin/echo`
    /// stands in for one, re-signed ad hoc so macOS's Gatekeeper
    /// application-bundle assessment does not suspend it at `_dyld_start`
    /// forever (mirrors `AdapterWiringTests.installStandInExecutable`
    /// exactly; duplicated here because that helper lives in the
    /// `PlaysteadTests` target, unreachable from the app target this file
    /// compiles into).
    private static func installStandInAdapterExecutable(in appURL: URL, at executableRelativePath: String) throws {
        let executableURL = appURL.appendingPathComponent(executableRelativePath)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", executableURL.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            throw DeterministicProfileError.stateMismatch("zero-network-play-flow: stand-in adapter could not be re-signed")
        }
    }

    private static func runZeroNetworkPlayFlow(root: URL, appEnvironment: AppEnvironment) async throws {
        let pin = try AdapterPin.load()
        let appURL = root.appendingPathComponent("ZeroNetworkStandIn.app", isDirectory: true)
        try installStandInAdapterExecutable(in: appURL, at: pin.launch.executableRelativePath)

        guard await appEnvironment.selectExistingAdapter(appURL: appURL) else {
            throw DeterministicProfileError.stateMismatch("zero-network-play-flow: stand-in adapter selection failed")
        }
        guard let host = await appEnvironment.adapterHost else {
            throw DeterministicProfileError.stateMismatch("zero-network-play-flow: no adapter host")
        }

        // A synthetic playable entry with one verified, locally committed
        // ROM member -- exactly `AdapterWiringTests.seedPlayableEntry`'s
        // shape, so the readiness gate the real Play flow calls actually
        // reports ready rather than being bypassed.
        let assetSetID = "zero-network-play-flow-asset"
        let romBytes = Data(repeating: 0xAB, count: 256)
        let romDigest = sha256Hex(of: romBytes)
        let partial = try await appEnvironment.appPaths.partialURL(for: romDigest)
        try await FileManager.default.createDirectory(at: appEnvironment.appPaths.partials, withIntermediateDirectories: true)
        try romBytes.write(to: partial)
        try await appEnvironment.casManager.commit(partialAt: partial, sha256: romDigest)

        let entry = CatalogueEntry(
            id: assetSetID, system: "gba", displayTitle: "Zero Network Play Flow", tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: romDigest, size: romBytes.count, name: "rom.gba")]
        )
        try await appEnvironment.catalogueStore.upsert(entry)

        let members = entry.members.compactMap { member -> (sha256: String, declaredName: String)? in
            guard let sha256 = member.sha256, let name = member.name else { return nil }
            return (sha256, name)
        }

        let report = await appEnvironment.readinessReport(for: entry)
        guard report.isReady else {
            throw DeterministicProfileError.stateMismatch("zero-network-play-flow: synthetic entry was not readiness-ready")
        }

        let materialized = try await appEnvironment.launchMaterializer.materialize(assetSetID: entry.id, members: members)
        guard let romURL = materialized.files.first else {
            throw DeterministicProfileError.stateMismatch("zero-network-play-flow: materialize produced no launchable member")
        }
        let saveDir = try await appEnvironment.saveDirectoryURL(forAssetSetID: entry.id)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        // The two fire-and-forget calls the real `GameRowView.play()` makes
        // between readiness and spawn -- exercised here unchanged, so a
        // stray request from either one is caught by the armed recorder.
        let sessionID = await appEnvironment.playSessionRecorder.began(assetSetID: entry.id)
        await appEnvironment.refreshCurationViewModels()

        let exited = SpawnExitSignal()
        _ = try await host.launch(assetSetID: entry.id, romPath: romURL.path, saveDir: saveDir.path) { _ in
            Task { @MainActor in
                appEnvironment.playSessionRecorder.ended(sessionID)
                appEnvironment.refreshCurationViewModels()
            }
            exited.signal()
        }
        try await exited.wait(timeoutSeconds: 20)
    }

    /// A tiny async-friendly exit latch — `AdapterHost.launch`'s `onExit`
    /// closure is `@Sendable`, non-async, and may fire on an arbitrary
    /// queue, so this hook cannot simply `await` the closure itself.
    private final class SpawnExitSignal: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func signal() { semaphore.signal() }
        func wait(timeoutSeconds: Int) async throws {
            let deadline = DispatchTime.now() + .seconds(timeoutSeconds)
            if semaphore.wait(timeout: deadline) == .timedOut {
                throw DeterministicProfileError.stateMismatch("zero-network-play-flow: adapter process never exited")
            }
        }
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
        let url = canonicalFileURL(raw)
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
        let url = canonicalFileURL(raw)
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

    /// Resolves existing symlink components before a containment comparison.
    /// `standardizedFileURL` alone preserves `/private/tmp`, while the root
    /// may already have the `/private/var/tmp` spelling. Resolving first also
    /// ensures that a symlink beneath an owned root cannot point outside it.
    private static func canonicalFileURL(_ raw: String) -> URL {
        let fileManager = FileManager.default
        var existingAncestor = URL(fileURLWithPath: raw).standardizedFileURL
        var unresolvedComponents: [String] = []

        // `resolvingSymlinksInPath()` leaves a nonexistent leaf's ancestors
        // untouched. Walk back to the nearest existing component, canonicalize
        // that component, then rebuild the leaf. This is necessary for the
        // fresh Keychain and report destinations created after validation.
        while !fileManager.fileExists(atPath: existingAncestor.path) {
            let component = existingAncestor.lastPathComponent
            guard !component.isEmpty, existingAncestor.path != "/" else { break }
            unresolvedComponents.append(component)
            existingAncestor.deleteLastPathComponent()
        }

        return unresolvedComponents.reversed().reduce(
            existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        ) { url, component in
            url.appendingPathComponent(component)
        }
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
