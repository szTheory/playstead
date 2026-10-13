import CryptoKit
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MetadataSettingsView: View {
    let games: [CatalogueEntry]
#if UI_TESTING
    private let fixture: MetadataSettingsStateFixture?
#endif
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedAssetSetID: String?
    @State private var preview: MetadataProviderPreview?
    @State private var candidates: [MetadataProviderEvidence] = []
    @State private var estimate: MetadataPreparationEstimate?
    @State private var jobs: [MetadataPreparationJob] = []
    @State private var selectedIDs: Set<String> = []
    @State private var cache = MetadataCacheSnapshot(budgetBytes: MetadataMediaCache.byteLimit, usedBytes: 0, pinnedItems: 0, expiringItems: 0, reclaimableBytes: 0)
    @State private var message: String?
    @State private var isLoading = false
    @State private var hashOptIn = false
    @State private var needsDisclosureReview = false
    @State private var reviewedDisclosureRevision: String?
    @State private var preparationMode = "balanced"
    @State private var showsReclaimConfirmation = false
    @State private var showsMediaPicker = false
    @State private var mediaAssetSetID: String?
    @State private var uploadProgress = 0.0
    @State private var isUploading = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var pendingUpload: (url: URL, assetSetID: String)?
    @State private var uploadedMedia: [MetadataPrivateMediaReceipt] = []
    @State private var verifiedOriginal: (sha256: String, size: Int)?
    @State private var localPreviewImage: NSImage?
    @State private var localPreviewText: String?

#if UI_TESTING
    init(games: [CatalogueEntry], fixture: MetadataSettingsStateFixture? = nil) {
        self.games = games
        self.fixture = fixture
        _selectedAssetSetID = State(initialValue: fixture?.selectedAssetSetID)
        _preview = State(initialValue: fixture?.preview)
        _candidates = State(initialValue: fixture?.candidates ?? [])
        _estimate = State(initialValue: fixture?.estimate)
        _jobs = State(initialValue: fixture?.jobs ?? [])
        _selectedIDs = State(initialValue: fixture?.selectedIDs ?? [])
        _cache = State(initialValue: fixture?.cache ?? MetadataCacheSnapshot(
            budgetBytes: MetadataMediaCache.byteLimit, usedBytes: 0, pinnedItems: 0, expiringItems: 0, reclaimableBytes: 0
        ))
        _message = State(initialValue: fixture?.message)
        _isLoading = State(initialValue: fixture?.isLoading ?? false)
        _hashOptIn = State(initialValue: false)
        _needsDisclosureReview = State(initialValue: fixture?.needsDisclosureReview ?? false)
        _reviewedDisclosureRevision = State(initialValue: fixture?.reviewedDisclosureRevision ?? fixture?.preview?.disclosureRevision)
        _preparationMode = State(initialValue: fixture?.preparationMode ?? "balanced")
        _showsReclaimConfirmation = State(initialValue: false)
        _showsMediaPicker = State(initialValue: false)
        _mediaAssetSetID = State(initialValue: fixture?.mediaAssetSetID)
        _uploadProgress = State(initialValue: fixture?.uploadProgress ?? 0)
        _uploadedMedia = State(initialValue: fixture?.uploadedMedia ?? [])
        _verifiedOriginal = State(initialValue: fixture?.verifiedOriginal)
        _localPreviewText = State(initialValue: fixture?.previewText.map { String($0.prefix(320)) })
    }
#endif

    private var coordinator: MetadataCoordinator { environment.metadataCoordinator }
    private var selectedGame: CatalogueEntry? { games.first { $0.id == selectedAssetSetID } }

    private var offersUploadRetry: Bool {
        if pendingUpload != nil { return true }
#if UI_TESTING
        return fixture?.fixtureIdentity == "local-media-form/rejected-error"
            || fixture?.fixtureIdentity == "local-media-form/overlarge-image"
#else
        return false
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Metadata").font(.psHeading)
            Text("\(games.count) available games").font(.psLabel)
                .accessibilityIdentifier("playstead.metadata.available-game-count")
#if UI_TESTING
            if let fixture {
                Text(fixture.fixtureIdentity ?? "").accessibilityIdentifier("playstead.metadata.fixture.identity")
                Button("Next metadata fixture") { environment.advanceUITestMetadataFixture() }
                    .accessibilityIdentifier("playstead.metadata.fixture.next")
            }
#endif
            Text("Optional text and artwork for your private library. Provider lookup stays off until you review and enable it.")
                .font(.psBody).foregroundStyle(DesignTokens.textMuted)

            GroupBox("Provider disclosure") {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    gamePicker
                    if let preview {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("Provider", value: preview.provider.uppercased())
                            LabeledContent("Exact query", value: preview.queryPreview)
                                .accessibilityIdentifier("playstead.metadata.consent.exact-query")
                            LabeledContent("System", value: preview.system)
                            Text(MetadataAPI.disclosureTerms).font(.psLabel).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("playstead.metadata.consent.disclosure")
                            if let termsURL = URL(string: preview.termsURL), termsURL.scheme == "https" { Link("Provider terms", destination: termsURL) }
                            Text("Provider results are text suggestions. Image rights are unverified, so provider images stay unavailable.")
                                .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                            if needsDisclosureReview {
                                Text("Provider terms changed. Review the current disclosure before enabling future requests.")
                                    .font(.psLabel).accessibilityIdentifier("playstead.metadata.consent.terms-changed")
                            }
                            Toggle("Allow a future local content-hash lookup (hash is never sent to IGDB)", isOn: $hashOptIn)
                                .disabled(true)
                                .accessibilityValue(hashOptIn ? "Enabled" : "Disabled")
                                .accessibilityIdentifier("playstead.metadata.consent.hash-opt-in")
                            if !preview.credentialsReady {
                                Label("The server owner has not configured provider credentials.", systemImage: "info.circle")
                                    .accessibilityIdentifier("playstead.metadata.consent.credentials")
                            }
                            HStack {
                                Button(needsDisclosureReview ? "Enable current disclosure" : (preview.enabled ? "Revoke provider access" : "Enable for this game")) {
                                    Task { await runProviderConsent(enabled: needsDisclosureReview || !preview.enabled) }
                                }
                                .disabled(isLoading || ((!preview.enabled || needsDisclosureReview) && (!preview.credentialsReady || preview.queryPreview.isEmpty)))
                                .accessibilityIdentifier("playstead.metadata.consent.toggle")
                                Button("Refresh disclosure") { Task { await loadPreview() } }
                                    .disabled(isLoading)
                            }
                            Button("Search suggestions") { Task { await search() } }
                                .disabled(isLoading || needsDisclosureReview || !preview.enabled || !preview.credentialsReady || !supportsProviderSearch(preview.system))
                                .accessibilityIdentifier("playstead.metadata.candidates.search")
                            if !supportsProviderSearch(preview.system) {
                                Text("Suggestions are supported for Game Boy, Game Boy Color, and Game Boy Advance only.")
                                    .font(.psLabel).accessibilityIdentifier("playstead.metadata.candidates.unsupported-system")
                            }
                        }
                    } else {
                        Button("Preview exact disclosure") { Task { await loadPreview() } }
                            .disabled(selectedAssetSetID == nil || isLoading)
                            .accessibilityIdentifier("playstead.metadata.consent.preview")
                    }
                    if isLoading { ProgressView("Working locally and with the paired server…").accessibilityIdentifier("playstead.metadata.progress") }
                    if let message { Text(message).font(.psLabel).accessibilityIdentifier("playstead.metadata.status") }
                    candidateList
                }
                .padding(.vertical, 4)
            }

            GroupBox("Preparation") {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Picker("Request level", selection: $preparationMode) {
                        Text("Balanced").tag("balanced")
                        Text("Minimal").tag("minimal")
                    }.pickerStyle(.segmented).accessibilityIdentifier("playstead.metadata.preparation.mode")
                    Text("Balanced is the default. Only selected games are included; the server shows its exact request, byte, and storage estimate before queueing.")
                        .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                    Text("\(selectedIDs.count) selected")
                        .font(.psLabel)
                        .accessibilityIdentifier("playstead.metadata.preparation.selection-count")
                    ForEach(games) { game in
                        Toggle(environment.displayTitle(for: game), isOn: Binding(
                            get: { selectedIDs.contains(game.id) },
                            set: { checked in
                                if checked { selectedIDs.insert(game.id) } else { selectedIDs.remove(game.id) }
                                estimate = nil
                            }
                        ))
                        .accessibilityIdentifier("playstead.metadata.preparation.game.\(game.id)")
                    }
                    HStack {
                        Button("Review estimate") { Task { await loadEstimate() } }
                            .disabled(selectedIDs.isEmpty || isLoading)
                            .accessibilityIdentifier("playstead.metadata.preparation.estimate")
                        if let estimate {
                            Text("\(selectedIDs.count) games · \(estimate.requests) requests · \(ByteCountFormatter.string(fromByteCount: Int64(estimate.bytes), countStyle: .file)) · \(ByteCountFormatter.string(fromByteCount: Int64(estimate.storage), countStyle: .file)) storage")
                                .accessibilityValue(Text(verbatim: "\(selectedIDs.count) games · \(estimate.requests) requests · \(estimate.bytes) bytes · \(estimate.storage) bytes storage"))
                                .accessibilityIdentifier("playstead.metadata.preparation.review")
                            Button("Queue selected") { Task { await enqueuePreparation() } }
                                .disabled(isLoading)
                                .accessibilityIdentifier("playstead.metadata.preparation.enqueue")
                        }
                    }
                    ForEach(jobs) { job in
                        HStack {
                            Text("\(job.state) · \(job.progress.stringValue ?? "working")")
                            Spacer()
                            if ["queued", "running"].contains(job.state) {
                                Button("Cancel") { Task { await cancel(jobID: job.id) } }
                            }
                        }.accessibilityIdentifier("playstead.metadata.preparation.job.\(job.id)")
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Private media cache") {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("Device budget: \(ByteCountFormatter.string(fromByteCount: Int64(cache.budgetBytes), countStyle: .file))")
                        .accessibilityIdentifier("playstead.metadata.cache.budget")
                    cacheRow("Used", value: ByteCountFormatter.string(fromByteCount: Int64(cache.usedBytes), countStyle: .file), identifier: "used", rawValue: "\(cache.usedBytes) bytes")
                    cacheRow("Pinned items", value: "\(cache.pinnedItems)", identifier: "pinned")
                    cacheRow("Expiring within seven days", value: "\(cache.expiringItems)", identifier: "expiring")
                    cacheRow("Reclaimable", value: ByteCountFormatter.string(fromByteCount: Int64(cache.reclaimableBytes), countStyle: .file), identifier: "reclaimable")
                    Text("Reclaim removes only unpinned derived artwork from this device. Imported originals, games, private uploads, and saves are untouched.")
                        .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                    LabeledContent("Server used", value: ByteCountFormatter.string(fromByteCount: Int64(cache.serverUsedBytes), countStyle: .file))
                    cacheRow("Server budget", value: ByteCountFormatter.string(fromByteCount: Int64(cache.serverBudgetBytes), countStyle: .file), identifier: "server-budget")
                    LabeledContent("Server reclaimable", value: ByteCountFormatter.string(fromByteCount: Int64(cache.serverReclaimableBytes), countStyle: .file))
                    Text("Provider image rights stay disabled until an exact grant exists.")
                        .font(.psLabel).accessibilityIdentifier("playstead.metadata.cache.image-rights")
                    Text("Target field: private cover artwork for PNG/JPEG; private description text for TXT.")
                        .font(.psLabel).accessibilityIdentifier("playstead.metadata.media.target")
                    if let localPreviewImage {
                        Image(nsImage: localPreviewImage)
                            .resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 160)
                            .accessibilityLabel("Bounded local artwork preview")
                            .accessibilityIdentifier("playstead.metadata.media.preview.image")
                    }
                    if let localPreviewText {
                        Text(localPreviewText).lineLimit(4).textSelection(.enabled)
                            .accessibilityIdentifier("playstead.metadata.media.preview.text")
                    }
                    HStack {
                        Button("Refresh usage") { Task { await refreshCache() } }
                        Button("Reclaim unpinned artwork") { showsReclaimConfirmation = true }
                            .disabled(cache.reclaimableBytes == 0)
                            .accessibilityIdentifier("playstead.metadata.cache.reclaim")
                        Button("Upload private media…") { showsMediaPicker = true }
                            .disabled(games.isEmpty || isUploading)
                            .accessibilityIdentifier("playstead.metadata.media.upload")
                    }
                    if isUploading {
                        ProgressView("Uploading private media…")
                            .accessibilityIdentifier("playstead.metadata.media.progress")
                        Button("Cancel upload", role: .cancel) { cancelUpload() }
                            .accessibilityIdentifier("playstead.metadata.media.cancel")
                    } else if offersUploadRetry {
                        Button("Retry upload") {
                            if pendingUpload != nil { retryUpload() }
                            else { showsMediaPicker = true }
                        }
                            .accessibilityIdentifier("playstead.metadata.media.retry")
                    }
#if UI_TESTING
                    HStack {
                        if let assetSetID = selectedAssetSetID {
                            if let path = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_PNG_FILE"] {
                                Button("Upload PNG fixture") { uploadFixture(path: path, assetSetID: assetSetID) }
                                    .accessibilityIdentifier("playstead.metadata.media.test-upload.png")
                            }
                            if let path = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_JPEG_FILE"] {
                                Button("Upload JPEG fixture") { uploadFixture(path: path, assetSetID: assetSetID) }
                                    .accessibilityIdentifier("playstead.metadata.media.test-upload.jpeg")
                            }
                            if let path = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_TEXT_FILE"] {
                                Button("Upload text fixture") { uploadFixture(path: path, assetSetID: assetSetID) }
                                    .accessibilityIdentifier("playstead.metadata.media.test-upload.text")
                            }
                            if let fixturePath = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_MEDIA_FILE"] {
                                Button("Upload local media fixture") { uploadFixture(path: fixturePath, assetSetID: assetSetID) }
                                    .accessibilityIdentifier("playstead.metadata.media.test-upload")
                            }
                        }
                    }
#endif
                    ForEach(uploadedMedia, id: \.id) { media in
                        HStack {
                            Text("Private original · \(media.originalSizeBytes) bytes · \(media.originalSHA256.prefix(12))…")
                            Button("Export and verify original") { Task { await verifyOriginal(media) } }
                            if media.derivedSHA256 != nil { Button("Select as cover") { Task { await selectCover(media) } } }
                        }.accessibilityIdentifier("playstead.metadata.media.\(media.id)")
                    }
                    if let verifiedOriginal { Text("Export verified · \(verifiedOriginal.size) bytes · SHA-256 \(verifiedOriginal.sha256)").accessibilityIdentifier("playstead.metadata.media.verified-original") }
                }.padding(.vertical, 4)
            }
        }
        .task {
            if selectedAssetSetID == nil {
#if UI_TESTING
                let requestedAssetID = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_ASSET_ID"]
                let requestedTitle = ProcessInfo.processInfo.environment["PLAYSTEAD_UI_TEST_METADATA_ASSET_TITLE"]
                selectedAssetSetID = games.first(where: {
                    $0.id == requestedAssetID && supportsProviderSearch($0.system)
                })?.id ?? games.first(where: {
                    $0.displayTitle == requestedTitle && supportsProviderSearch($0.system)
                })?.id ?? games.first?.id
#else
                selectedAssetSetID = games.first?.id
#endif
            }
#if UI_TESTING
            if fixture?.simulateUpload == true, !isUploading {
                startFixtureUpload()
            }
            if fixture == nil { await refreshCache() }
#else
            await refreshCache()
#endif
        }
        .confirmationDialog("Reclaim unpinned artwork?", isPresented: $showsReclaimConfirmation, titleVisibility: .visible) {
            Button("Reclaim artwork", role: .destructive) { Task { await reclaimCache() } }
        } message: { Text("Only derived artwork in this device cache is removed.") }
        .fileImporter(isPresented: $showsMediaPicker, allowedContentTypes: [.png, .jpeg, .plainText], allowsMultipleSelection: false) { result in
            guard let url = try? result.get().first, let id = selectedAssetSetID else { message = "Choose one local file to upload."; return }
            mediaAssetSetID = id
            beginUpload(url: url, assetSetID: id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playstead.settings.metadata")
    }

    private func cacheRow(_ title: String, value: String, identifier: String, rawValue: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .accessibilityValue(Text(verbatim: rawValue ?? value))
                .accessibilityIdentifier("playstead.metadata.cache.\(identifier)")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var gamePicker: some View {
        if games.isEmpty {
            Text("Import a game before reviewing provider disclosure.").accessibilityIdentifier("playstead.metadata.consent.empty")
        } else {
            Picker("Game", selection: $selectedAssetSetID) {
                ForEach(games) { game in Text(environment.displayTitle(for: game)).tag(Optional(game.id)) }
            }.onChange(of: selectedAssetSetID) { _, _ in preview = nil; candidates = []; message = nil }
                .accessibilityIdentifier("playstead.metadata.game-picker")
                .accessibilityValue(selectedGame.map { "\($0.displayTitle) · \($0.system)" } ?? "No game selected")
        }
    }

    @ViewBuilder private var candidateList: some View {
        if candidates.isEmpty {
            Text("No provider suggestion selected. Search results never auto-match.")
                .font(.psLabel).accessibilityIdentifier("playstead.metadata.candidates.empty")
        } else {
            Text("\(candidates.count) suggestion\(candidates.count == 1 ? "" : "s")")
                .accessibilityIdentifier("playstead.metadata.candidates.count")
            ForEach(candidates) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title).font(.psLabel)
                    Text("\(candidate.system) · \(candidate.confidence) confidence · \(candidate.attribution)")
                        .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                    if let termsURL = URL(string: candidate.termsURL), termsURL.scheme == "https" { Link("Terms", destination: termsURL) }
                    Button("Select this title") { Task { await select(candidate) } }
                        .accessibilityIdentifier("playstead.metadata.candidate.select.\(candidate.id)")
                }.padding(.vertical, 4)
            }
        }
    }

    @MainActor private func loadPreview() async {
        guard let selectedAssetSetID else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let refreshed = try await coordinator.preview(assetSetID: selectedAssetSetID)
            if let reviewedDisclosureRevision, reviewedDisclosureRevision != refreshed.disclosureRevision {
                needsDisclosureReview = true
            }
            preview = refreshed
            message = "Disclosure preview is current."
        }
        catch { message = "Provider disclosure could not be loaded. Check the paired server and retry." }
    }

    @MainActor private func runProviderConsent(enabled: Bool) async {
        guard let selectedAssetSetID, let preview else { return }
        isLoading = true; defer { isLoading = false }
        do {
            try await coordinator.consent(assetSetID: selectedAssetSetID, preview: preview, enabled: enabled)
            self.preview = try await coordinator.preview(assetSetID: selectedAssetSetID)
            if enabled {
                reviewedDisclosureRevision = self.preview?.disclosureRevision
                needsDisclosureReview = false
            }
            message = enabled ? "Provider access enabled for the displayed title and system." : "Provider access revoked."
        } catch MetadataAPIError.cacheCleanupPending {
            self.preview = try? await coordinator.preview(assetSetID: selectedAssetSetID)
            message = "Provider access revoked. Cached provider artwork cleanup failed; retry Reclaim provider cache."
        } catch { message = "Consent could not be saved. No search was sent." }
    }

    @MainActor private func search() async {
        guard let selectedAssetSetID, let preview, preview.enabled, supportsProviderSearch(preview.system) else { return }
        isLoading = true; defer { isLoading = false }
        do { candidates = try await coordinator.search(assetSetID: selectedAssetSetID); message = "Suggestions loaded; choose one explicitly." }
        catch { message = "Suggestions are unavailable. Consent and local metadata remain intact." }
    }

    private func supportsProviderSearch(_ system: String) -> Bool {
        ["gb", "gbc", "gba"].contains(system.lowercased())
    }

    @MainActor private func select(_ candidate: MetadataProviderEvidence) async {
        guard let selectedAssetSetID else { return }
        do {
            _ = try await coordinator.selectProviderEvidence(assetSetID: selectedAssetSetID, field: "title", evidenceID: candidate.id)
            message = "Selected title saved with provider evidence."
        } catch { message = "The title could not be saved; review the current value and retry." }
    }

    @MainActor private func loadEstimate() async {
        let ids = games.filter { selectedIDs.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        do { estimate = try await coordinator.estimate(assetSetIDs: ids, mode: preparationMode); message = "Review this estimate before queueing." }
        catch { estimate = nil; message = "Estimate unavailable. Enable current consent for each selected game." }
    }

    @MainActor private func enqueuePreparation() async {
        guard let selectedGame, let estimate else { return }
        isLoading = true; defer { isLoading = false }
        do { jobs = try await coordinator.prepare(assetSetID: selectedGame.id, selectedIDs: Array(selectedIDs).sorted(), estimate: estimate); message = "Preparation queued." }
        catch { message = "Queue request failed or the estimate changed. Review a fresh estimate." }
    }

    @MainActor private func cancel(jobID: String) async {
        do { let updated = try await coordinator.cancel(jobID: jobID); jobs = jobs.map { $0.id == jobID ? updated : $0 } }
        catch { message = "The job could not be canceled; refresh its durable status." }
    }

    @MainActor private func selectCover(_ media: MetadataPrivateMediaReceipt) async {
        guard let assetSetID = mediaAssetSetID, let digest = media.derivedSHA256,
              let size = media.derivedSizeBytes else { return }
        do {
            let value: JSONValue = .object(["media_id": .string(media.id), "sha256": .string(digest),
                                            "size_bytes": .int(size), "caption": .string("Private artwork")])
            _ = try await coordinator.select(assetSetID: assetSetID, field: "cover", value: value)
            message = "Private artwork selected. The original remains separately exportable."
        } catch { message = "The private cover could not be selected." }
    }

    @MainActor private func verifyOriginal(_ media: MetadataPrivateMediaReceipt) async {
        guard let assetSetID = mediaAssetSetID else { return }
        do {
            let bytes = try await coordinator.original(assetSetID: assetSetID, mediaID: media.id)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard digest == media.originalSHA256, bytes.count == media.originalSizeBytes else { throw MetadataAPIError.receiptMismatch }
            verifiedOriginal = (digest, bytes.count)
            message = "Original export matches its immutable receipt."
        } catch { message = "Original export could not be verified against its receipt." }
    }

    @MainActor private func refreshCache() async {
        do { cache = try await coordinator.cacheSnapshot() }
        catch { message = "Cache usage is unavailable until the paired server reconnects." }
    }
    @MainActor private func reclaimCache() async {
        do { try await coordinator.reclaimCache(); await refreshCache(); message = "Unpinned derived artwork reclaimed." }
        catch { message = "The local cache could not be reclaimed." }
    }

    @MainActor private func beginUpload(url: URL, assetSetID: String) {
        pendingUpload = (url, assetSetID)
        mediaAssetSetID = assetSetID
        localPreviewImage = nil
        localPreviewText = nil
        isUploading = true
        uploadProgress = 0.1
        uploadTask = Task { await upload(url: url, assetSetID: assetSetID) }
    }

    @MainActor private func retryUpload() {
        guard let pendingUpload else { return }
        beginUpload(url: pendingUpload.url, assetSetID: pendingUpload.assetSetID)
    }

    @MainActor private func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        uploadProgress = 0
        pendingUpload = nil
        message = "Upload canceled. Any accepted private original remains safe."
    }

    @MainActor private func upload(url: URL, assetSetID: String) async {
        let didStartScope = url.startAccessingSecurityScopedResource()
        if url.isFileURL && !didStartScope {
            // Files selected through the system panel are security scoped;
            // deterministic test files live in the app's already-authorized
            // isolated profile root and do not vend a security scope.
#if !UI_TESTING
            message = "The selected file is not accessible."; return
#endif
        }
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= MetadataAPI.maxPrivateMediaBytes else {
                throw MetadataAPIError.invalidPrivateMedia
            }
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let ext = url.pathExtension.lowercased()
            let mime = ext == "png" ? "image/png" : (ext == "jpg" || ext == "jpeg" ? "image/jpeg" : (ext == "txt" ? "text/plain" : ""))
            guard !Task.isCancelled else { throw CancellationError() }
            updateLocalPreview(bytes: bytes, mime: mime)
            uploadProgress = 0.5
            let receipt = try await coordinator.uploadPrivateMedia(assetSetID: assetSetID, bytes: bytes, mime: mime)
            // A returned receipt proves the server accepted the immutable
            // original. Keep it visible even if cancellation raced the reply.
            uploadedMedia.append(receipt)
            pendingUpload = nil
            uploadProgress = 1
            message = "Private media saved · \(receipt.originalSizeBytes) bytes · SHA-256 \(receipt.originalSHA256)"
        } catch is CancellationError {
            uploadProgress = 0
            message = "Upload canceled. Any accepted private original remains safe."
        } catch {
            uploadProgress = 0
            message = "Upload rejected. Retry the same bounded file or choose another."
        }
        isUploading = false
        uploadTask = nil
    }

    @MainActor private func updateLocalPreview(bytes: Data, mime: String) {
        if mime == "text/plain" {
            localPreviewText = String(data: bytes, encoding: .utf8).map { String($0.prefix(320)) }
            return
        }
        guard ["image/png", "image/jpeg"].contains(mime),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
              ] as CFDictionary) else { return }
        localPreviewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

#if UI_TESTING
    @MainActor private func uploadFixture(path: String, assetSetID: String) {
        beginUpload(url: URL(fileURLWithPath: path), assetSetID: assetSetID)
    }

    @MainActor private func startFixtureUpload() {
        isUploading = true
        uploadProgress = 0.5
        uploadTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(30))
                isUploading = false
                message = "Upload fixture completed."
            } catch {
                isUploading = false
                uploadProgress = 0
                message = "Upload canceled. Any accepted private original remains safe."
            }
            uploadTask = nil
        }
    }
#endif
}

#if UI_TESTING
struct MetadataSettingsStateFixture {
    var selectedAssetSetID: String? = nil
    var preview: MetadataProviderPreview? = nil
    var candidates: [MetadataProviderEvidence] = []
    var estimate: MetadataPreparationEstimate? = nil
    var jobs: [MetadataPreparationJob] = []
    var selectedIDs: Set<String> = []
    var cache: MetadataCacheSnapshot? = nil
    var message: String? = nil
    var isLoading = false
    var preparationMode = "balanced"
    var mediaAssetSetID: String? = nil
    var uploadProgress = 0.0
    var simulateUpload = false
    var uploadedMedia: [MetadataPrivateMediaReceipt] = []
    var verifiedOriginal: (sha256: String, size: Int)? = nil
    var fixtureIdentity: String? = nil
    var testGames: [CatalogueEntry] = []
    var previewText: String? = nil
    var needsDisclosureReview = false
    var reviewedDisclosureRevision: String? = nil
}
#endif
