#if UI_TESTING
import Foundation
import CryptoKit

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
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
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
        let data = try JSONSerialization.data(withJSONObject: result)
        try data.write(to: resultURL, options: .atomic)
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
