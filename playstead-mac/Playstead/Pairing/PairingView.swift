import AppKit
import SwiftUI
#if UI_TESTING
import CryptoKit
import CoreFoundation
import Darwin
#endif

#if UI_TESTING
private struct UITestRecoveryFixtureContract {
    let fixtureID: String
    let systemID: String
    let romSHA256: String
    let romSizeBytes: Int
    let saveSHA256: String
    let saveSizeBytes: Int

    static func load(profileRoot: String?) -> (status: String, fixture: Self?) {
        guard let profileRoot, !profileRoot.isEmpty else { return ("registry_missing", nil) }
        let root = URL(fileURLWithPath: profileRoot, isDirectory: true)
        let file = root.appendingPathComponent("recovery-fixture.json", isDirectory: false)
        let manager = FileManager.default
        guard
            (try? manager.destinationOfSymbolicLink(atPath: root.path)) == nil,
            let rootAttributes = try? manager.attributesOfItem(atPath: root.path),
            (rootAttributes[.type] as? FileAttributeType) == .typeDirectory,
            (rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
            (rootAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            (try? manager.destinationOfSymbolicLink(atPath: file.path)) == nil,
            let attributes = try? manager.attributesOfItem(atPath: file.path),
            (attributes[.type] as? FileAttributeType) == .typeRegular,
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            let size = (attributes[.size] as? NSNumber)?.intValue,
            size > 0, size <= 4096,
            let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == Set([
                "schema", "fixture_id", "system_id", "rom_sha256", "rom_size_bytes",
                "save_sha256", "save_size_bytes"
            ]),
            let schema = object["schema"] as? String,
            schema == "playstead.recovery-ui-fixture.v1",
            let fixtureID = object["fixture_id"] as? String,
            fixtureID == "aerevenadvance",
            let systemID = object["system_id"] as? String,
            systemID == "gba",
            let romSHA256 = object["rom_sha256"] as? String,
            romSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
            let romSizeNumber = object["rom_size_bytes"] as? NSNumber,
            CFGetTypeID(romSizeNumber) == CFNumberGetTypeID(),
            romSizeNumber.intValue > 0,
            let saveSHA256 = object["save_sha256"] as? String,
            saveSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
            let saveSizeNumber = object["save_size_bytes"] as? NSNumber,
            CFGetTypeID(saveSizeNumber) == CFNumberGetTypeID(),
            saveSizeNumber.intValue == 32_768
        else { return ("registry_invalid", nil) }

        return ("valid", Self(
            fixtureID: fixtureID,
            systemID: systemID,
            romSHA256: romSHA256,
            romSizeBytes: romSizeNumber.intValue,
            saveSHA256: saveSHA256,
            saveSizeBytes: saveSizeNumber.intValue
        ))
    }
}

/// A fail-closed bridge for the local recovery UI test. macOS Open panels are
/// not consistently automatable under headless XCTest, so the test supplies
/// its retained CA candidate only to this debug-only build. Production
/// configurations compile the bridge out and always use the native picker.
private enum UITestRecoveryCACandidate {
    static let pathKey = "PLAYSTEAD_UI_TEST_RECOVERY_CA_PATH"

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> (name: String, data: Data)? {
        guard let raw = environment[pathKey], !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        guard url.lastPathComponent == "caddy-root-ca.pem",
              url.deletingLastPathComponent().lastPathComponent.lowercased().hasPrefix("playstead")
        else { return nil }

        let roots = [
            fileManager.temporaryDirectory.standardizedFileURL,
            URL(fileURLWithPath: "/private/tmp", isDirectory: true).standardizedFileURL
        ]
        let pathComponents = url.pathComponents
        guard roots.contains(where: { root in
            let components = root.pathComponents
            return pathComponents.count > components.count
                && Array(pathComponents.prefix(components.count)) == components
        }) else { return nil }

        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o600,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty, data.count <= 16_384
        else { return nil }
        return (url.lastPathComponent, data)
    }
}

private enum UITestRecoveryTargetURL {
    static let fileName = "recovery-target.url"

    private static func value(environment: [String: String]) -> String? {
        guard let rawRoot = environment["PLAYSTEAD_UI_TEST_LIVE_ROOT"], !rawRoot.isEmpty else { return nil }
        let root = URL(fileURLWithPath: rawRoot).standardizedFileURL
        let url = root.appendingPathComponent(fileName, isDirectory: false)
        let fileManager = FileManager.default
        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o600,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > 0, size <= 4096,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func status(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        guard let raw = value(environment: environment) else { return "missing" }
        guard let components = URLComponents(string: raw) else { return "malformed" }
        guard components.scheme?.lowercased() == "https" else { return "scheme" }
        guard components.host?.lowercased() == "localhost" else { return "host" }
        guard let port = components.port, (1...65_535).contains(port) else { return "port" }
        guard components.user == nil, components.password == nil else { return "userinfo" }
        guard components.path.isEmpty || components.path == "/" else { return "path" }
        guard components.query == nil else { return "query" }
        guard components.fragment == nil else { return "fragment" }
        return "valid"
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard status(environment: environment) == "valid" else { return nil }
        return value(environment: environment)
    }
}
#endif

/// Posted by the app menu's "Pair with Server…" command (see
/// `PlaysteadApp`'s `.commands`) so an already-paired user can re-pair
/// against a new server from a second reachable call site, independent of
/// the empty-state action button `LibraryShellView` presents.
extension Notification.Name {
    static let presentPairingSheetRequested = Notification.Name("dev.playstead.mac.presentPairingSheetRequested")
}

/// The pairing ceremony surface, shaped after `AdapterSetupView`: a small
/// setup screen that drives a long-running async operation with progress
/// and typed failure states, rather than inventing a new shape.
///
/// This view owns no ceremony logic itself — every step (request, poll,
/// redeem, persist) lives in `PairingCoordinator`, which this view only
/// observes and drives. That split is deliberate (WINDOWS #37/#45's own
/// failure mode): a `private @MainActor` view method is a step no test can
/// drive.
struct PairingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var coordinator: PairingCoordinator?
    @State private var serverURLText: String = ""
    @State private var recoveryTrustAnchorName: String?
    @State private var recoveryCAError: String?
#if UI_TESTING
    @State private var recoveryCAUIStatus = "idle"
    @State private var recoveryCachePreflightStatus = "pending"
    @State private var recoveryCachePreflightBlockers = "pending"
    @State private var recoveryFixtureMatchStatus = "pending"
    @State private var recoveryFixtureAssetSetID = ""
    @State private var recoveryFixtureSaveStatus = "pending"
    @State private var recoveryFixtureMaterializationStatus = "pending"
#endif

    init() {
#if UI_TESTING
        _serverURLText = State(initialValue: UITestRecoveryTargetURL.resolve() ?? "")
#else
        _serverURLText = State(initialValue: "")
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let coordinator {
                content(for: coordinator.state, coordinator: coordinator)
            } else {
                Text("Pairing is unavailable in this build.")
                    .font(.psBody)
                    .foregroundColor(DesignTokens.textPrimary)
            }
#if UI_TESTING
            // These observe the app's durable sync/readiness state, so they
            // remain available when the recovery test returns from Settings.
            // A newly opened pairing form must not require another ceremony.
            if UITestBootstrap.isRequested() {
                Group {
                    Text(recoveryCursorStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-cursor-status")
                        .accessibilityValue(recoveryCursorStatus)
                    Text(recoveryCachePreflightStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-cache-preflight-status")
                        .accessibilityValue(recoveryCachePreflightStatus)
                    Text(recoveryCachePreflightBlockers)
                        .accessibilityIdentifier("playstead.readout.recovery-cache-preflight-blockers")
                        .accessibilityValue(recoveryCachePreflightBlockers)
                    Text(recoveryFixtureMatchStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-fixture-match-status")
                        .accessibilityValue(recoveryFixtureMatchStatus)
                    Text("fixture asset")
                        .accessibilityIdentifier("playstead.readout.recovery-fixture-asset-set-id")
                        .accessibilityValue(recoveryFixtureAssetSetID)
                    Text(recoveryFixtureSaveStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-fixture-save-status")
                        .accessibilityValue(recoveryFixtureSaveStatus)
                    Text(recoveryFixtureMaterializationStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-fixture-materialization-status")
                        .accessibilityValue(recoveryFixtureMaterializationStatus)
                }
            }
#endif
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if coordinator == nil {
                coordinator = environment.makePairingCoordinator()
            }
        }
        .onDisappear {
            // The user closing the sheet must stop the poll loop rather
            // than let it keep polling a request nothing will ever redeem.
            coordinator?.cancel()
        }
#if UI_TESTING
        .task(id: recoveryCursorStatus) {
            refreshRecoveryFixtureReadouts()
        }
#endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pairing")
    }

    @ViewBuilder
    private func content(for state: PairingState, coordinator: PairingCoordinator) -> some View {
        switch state {
        case .idle:
            form(coordinator: coordinator, error: nil)
        case .failed(let error):
            form(coordinator: coordinator, error: error)
        case .requesting:
            ProgressView("Requesting…")
        case .awaitingApproval(let displayCode, _):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Approve this code in your server's devices console:")
                    .font(.psBody)
                    .foregroundColor(DesignTokens.textPrimary)
                Text(displayCode)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundColor(DesignTokens.textPrimary)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingDisplayCode)
                if let devicesURL {
                    Text(devicesURL.absoluteString)
                        .textSelection(.enabled)
                    Button("Copy Devices URL") { copy(devicesURL.absoluteString) }
                }
                ProgressView()
            }
        case .redeeming:
            ProgressView("Finishing pairing…")
        case .paired:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("This Mac is paired.")
                    .font(.psBody)
                    .foregroundColor(DesignTokens.textPrimary)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingSuccess)
            }
        }
    }

    private func form(coordinator: PairingCoordinator, error: PairingError?) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
#if UI_TESTING
            if UITestBootstrap.isRequested() {
                Group {
                    Text(UITestRecoveryTargetURL.status())
                        .accessibilityIdentifier("playstead.readout.recovery-target-prefill")
                    Text(recoveryCAUIStatus)
                        .accessibilityIdentifier("playstead.readout.recovery-ca-candidate-status")
                        .accessibilityValue(recoveryCAUIStatus)
                }
            }
#endif
            Text("Enter your Playstead server's address to pair this Mac.")
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
            TextField("https://your-server.example.com", text: $serverURLText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingServerURL)
            if let error {
                Text(Self.describe(error))
                    .font(.psLabelEmphasized)
                    .foregroundColor(StatusToken.missingDependency)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("playstead.readout.pairing-error")
#if UI_TESTING
                    .accessibilityValue(Self.safeErrorCategory(error))
#endif
                Button("Copy error") { copy(Self.describe(error)) }
            }
            if let recoveryTrustAnchorName {
                Text("Recovery CA selected: \(recoveryTrustAnchorName)")
                    .font(.psLabelEmphasized)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Readout.pairingCASelection)
            }
            if let recoveryCAError {
                Text(recoveryCAError)
                    .font(.psLabelEmphasized)
                    .foregroundColor(StatusToken.missingDependency)
                    .accessibilityIdentifier("playstead.readout.pairing-ca-error")
            }
            Button("Choose recovery CA…") { chooseRecoveryCA() }
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.chooseRecoveryCA)
            Button(error == nil ? "Request pairing" : "Retry pairing") {
                let url = serverURLText
                Task { await coordinator.start(baseURLString: url) }
            }
            .disabled(serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(AccessibilityIdentifiers.Control.requestPairing)
        }
    }

    /// Every server refusal is a distinct, actionable message — never a
    /// generic "pairing failed" (PROT-01/ceremony-failure).
    ///
    /// `static`, not `private static` (WR-02): asserted directly by
    /// `PairingReachabilityTests` so the copy for a shared state stays true
    /// on every path that can reach it, not just the one this view happened
    /// to name in the switch statement.
    static func describe(_ error: PairingError) -> String {
        switch error {
        case .expired:
            return "This pairing request expired. Request a new code."
        case .alreadyRedeemed:
            return "This code was already used to pair a device. Request a new code."
        case .notApproved:
            return "This pairing request has not been approved yet. Approve it in the server's devices console."
        case .slowDown:
            // WR-02: this state is reached from three distinct paths -- the
            // automatic poll backoff, and a 429 on the request and redeem
            // calls, where nothing is polling. The copy must stay true on
            // all three, so it names the server's ask and the app's retry
            // rather than a polling cadence specific to only one path.
            return "The server asked this Mac to wait a moment. Playstead will retry shortly."
        case .notFound:
            return "This pairing request could not be found. Request a new code."
        case .denied:
            return "This pairing request was denied."
        case .keychainWriteFailed:
            return "Pairing succeeded, but the credential could not be saved to the Keychain."
        case .invalidResponse:
            return "The server address is not valid, or it sent an unexpected response."
        case .transport:
            return "Could not reach the server. Check the address and your connection."
        case .insecureServerAddress:
            return "The server address must start with https:// so this Mac can verify the server's certificate."
        case .certificatePinFailed:
            return "Pairing was undone because the server's certificate could not be saved. Try again."
        case .certificateTrustFailed:
            return "This server's certificate is not trusted. Choose the recovery CA supplied with this server, then retry."
        }
    }

#if UI_TESTING
    private static func safeErrorCategory(_ error: PairingError) -> String {
        switch error {
        case .expired: return "expired"
        case .alreadyRedeemed: return "already_redeemed"
        case .notApproved: return "not_approved"
        case .slowDown: return "slow_down"
        case .notFound: return "not_found"
        case .denied: return "denied"
        case .invalidResponse: return "invalid_response"
        case .keychainWriteFailed: return "keychain_write_failed"
        case .transport: return "transport"
        case .insecureServerAddress: return "insecure_address"
        case .certificatePinFailed: return "certificate_pin"
        case .certificateTrustFailed: return "certificate_trust"
        }
    }
#endif

    private var devicesURL: URL? {
        guard var components = URLComponents(string: serverURLText) else { return nil }
        components.path = "/devices"
        components.query = nil
        return components.url
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func chooseRecoveryCA() {
#if UI_TESTING
        if ProcessInfo.processInfo.environment[UITestRecoveryCACandidate.pathKey] != nil {
            recoveryCAUIStatus = "candidate_supplied"
            guard let candidate = UITestRecoveryCACandidate.load() else {
                recoveryCAUIStatus = "candidate_unavailable"
                recoveryCAError = "The selected recovery CA could not be loaded."
                recoveryTrustAnchorName = nil
                return
            }
            recoveryCAUIStatus = "candidate_loaded"
            selectRecoveryCA(data: candidate.data, name: candidate.name)
            return
        }
        recoveryCAUIStatus = "native_picker"
#endif
        let panel = NSOpenPanel()
        // Recovery bundles commonly contain either a DER certificate or a
        // PEM text certificate. Restricting the panel to `.data` hides the
        // latter even though `PinnedCertificateCapture` safely parses it.
        panel.allowedContentTypes = [.data, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url)
        else { return }
        selectRecoveryCA(data: data, name: url.lastPathComponent)
    }

    private func selectRecoveryCA(data: Data, name: String) {
        guard let certificateData = PinnedCertificateCapture.certificateData(fromRecoveryFile: data) else {
#if UI_TESTING
            recoveryCAUIStatus = "candidate_invalid"
#endif
            recoveryTrustAnchorName = nil
            recoveryCAError = "The selected recovery CA is not a valid certificate."
            return
        }
#if UI_TESTING
        recoveryCAUIStatus = "selected"
#endif
        recoveryTrustAnchorName = name
        recoveryCAError = nil
        coordinator = environment.makePairingCoordinator(suppliedTrustAnchorData: certificateData)
    }

#if UI_TESTING
    private func refreshRecoveryFixtureReadouts() {
        guard recoveryCursorStatus == "synced" else {
            recoveryFixtureMatchStatus = "sync_pending"
            recoveryFixtureAssetSetID = ""
            recoveryFixtureSaveStatus = "sync_pending"
            recoveryFixtureMaterializationStatus = "not_materialized"
            recoveryCachePreflightStatus = "blocked"
            recoveryCachePreflightBlockers = "game_assets"
            return
        }

        let loaded = UITestRecoveryFixtureContract.load(
            profileRoot: ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_LIVE_ROOT"]
        )
        guard let fixture = loaded.fixture else {
            recoveryFixtureMatchStatus = loaded.status
            recoveryFixtureAssetSetID = ""
            recoveryFixtureSaveStatus = "registry_unavailable"
            recoveryFixtureMaterializationStatus = "not_materialized"
            recoveryCachePreflightStatus = "blocked"
            recoveryCachePreflightBlockers = "game_assets"
            return
        }

        let matches = environment.libraryViewModel.catalogue.filter { entry in
            entry.system == fixture.systemID && entry.members.contains { member in
                member.required && member.role == "primary" &&
                    member.sha256 == fixture.romSHA256 && member.size == fixture.romSizeBytes
            }
        }
        guard matches.count == 1, let entry = matches.first else {
            recoveryFixtureMatchStatus = matches.isEmpty ? "game_missing" : "game_ambiguous"
            recoveryFixtureAssetSetID = ""
            recoveryFixtureSaveStatus = "game_unmatched"
            recoveryFixtureMaterializationStatus = "not_materialized"
            recoveryCachePreflightStatus = "blocked"
            recoveryCachePreflightBlockers = matches.isEmpty ? "game_assets" : "cache_verification"
            return
        }

        recoveryFixtureMatchStatus = "matched"
        recoveryFixtureAssetSetID = entry.id
        let report = environment.readinessReport(for: entry)
        let blockedKinds = Set(report.checks.filter(\.outcome.isBlocking).map(\.kind))
        recoveryCachePreflightBlockers = ReadinessCheckKind.allCases
            .filter { blockedKinds.contains($0) }
            .map(recoveryBlockerName)
            .joined(separator: ",")
        recoveryCachePreflightStatus = report.isReady ? "ready" : "blocked"

        let saveEvidence = recoveryFixtureSaveEvidence(for: entry, fixture: fixture)
        recoveryFixtureSaveStatus = saveEvidence.saveStatus
        recoveryFixtureMaterializationStatus = saveEvidence.materializationStatus
    }

    private func recoveryFixtureSaveEvidence(
        for entry: CatalogueEntry,
        fixture: UITestRecoveryFixtureContract
    ) -> (saveStatus: String, materializationStatus: String) {
        let contentKey = AppEnvironment.saveContentKey(for: entry)
        guard let line = environment.saveStore.fetchLine(
            contentKey: contentKey, saveKind: "battery", slot: "0"
        ) else { return ("line_missing", "not_materialized") }

        let revision = environment.saveStore.fetchRevisions(saveLineID: line.id).first {
            $0.blobSHA256 == fixture.saveSHA256 && $0.sizeBytes == fixture.saveSizeBytes
        }
        guard let revision else { return ("revision_missing", "not_materialized") }
        guard revision.durability == SaveDurability.uploaded.rawValue else {
            return ("revision_not_uploaded", "not_materialized")
        }
        guard
            environment.casManager.contains(fixture.saveSHA256),
            let casURL = try? environment.casManager.objectURL(for: fixture.saveSHA256),
            Self.recoveryFixtureFileMatches(casURL, sha256: fixture.saveSHA256, size: fixture.saveSizeBytes)
        else { return ("prefetch_missing_or_mismatched", "not_materialized") }

        let romName = entry.members.first {
            $0.required && $0.role == "primary" && $0.sha256 == fixture.romSHA256
        }?.name
        guard let romName, let saveDirectory = try? environment.saveDirectoryURL(forAssetSetID: entry.id) else {
            return ("prefetched", "save_path_unavailable")
        }
        let saveURL = SaveCapturePaths.targetURL(saveDirectory: saveDirectory, romFileName: romName)
        guard Self.recoveryFixtureFileMatches(saveURL, sha256: fixture.saveSHA256, size: fixture.saveSizeBytes) else {
            return ("prefetched", "not_materialized")
        }
        guard revision.restoredHereAt != nil else {
            return ("prefetched", "materialization_unconfirmed")
        }
        return ("prefetched", "materialized")
    }

    private static func recoveryFixtureFileMatches(_ url: URL, sha256: String, size: Int) -> Bool {
        let manager = FileManager.default
        guard
            (try? manager.destinationOfSymbolicLink(atPath: url.path)) == nil,
            let attributes = try? manager.attributesOfItem(atPath: url.path),
            (attributes[.type] as? FileAttributeType) == .typeRegular,
            (attributes[.size] as? NSNumber)?.intValue == size,
            let bytes = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            bytes.count == size
        else { return false }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return digest == sha256
    }

    private func recoveryBlockerName(_ kind: ReadinessCheckKind) -> String {
        switch kind {
        case .gameAssets: "game_assets"
        case .cacheVerification: "cache_verification"
        case .emulator: "emulator"
        case .bios: "bios"
        case .controllerAndInput: "controller_and_input"
        case .saveDirectory: "save_directory"
        case .saveState: "save_state"
        }
    }

    private var recoveryCursorStatus: String {
        switch environment.libraryViewModel.syncState {
        case .neverSynced: return "never_synced"
        case .syncing: return "syncing"
        case .synced: return "synced"
        case .offline: return "offline"
        }
    }
#endif
}
