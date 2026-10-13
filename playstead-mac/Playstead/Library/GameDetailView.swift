import SwiftUI

struct GameDetailView: View {
    let entry: CatalogueEntry
    let onPlay: () -> Void
    let onShowReadiness: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismissAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsGallery = false
    @State private var showsMetadataCorrection = false
    @FocusState private var galleryTriggerFocused: Bool

    private var metadata: MetadataSelection? { environment.metadataSelection(for: entry.id) }
    private var title: String { environment.displayTitle(for: entry) }
    private var screenshots: [MetadataArtworkReference] { metadata?.selectedScreenshots ?? [] }
    private var gameStatus: GameRowStatus { GameRowView.status(for: environment.readinessReport(for: entry)) }

    private var primaryActionTitle: String {
        switch gameStatus {
        case .needsDownload, .error: "Download"
        case .checking: "Checking readiness"
        case .downloading: "Downloading"
        case .ready: "Play"
        case .blocked: "What's needed"
        }
    }

    private var primaryAction: () -> Void {
        if case .blocked = gameStatus { return onShowReadiness }
        return onPlay
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                    ArtworkThumbnailView(
                        assetSetID: entry.id,
                        systemID: entry.system,
                        reference: metadata?.selectedCover,
                        frameSize: ArtworkThumbnailView.detailCoverSize,
                        accessibilityID: "playstead.game.\(entry.id).details.cover",
                        accessibleLabel: "Game cover for \(title)"
                    )
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text(title)
                            .font(.psDisplay)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("playstead.game.\(entry.id).detail-title")
                        Text(SystemRegistry.entry(for: entry.system).displayName)
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                        Button(primaryActionTitle, action: primaryAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(gameStatus == .checking || gameStatus == .downloading)
                            .accessibilityIdentifier("playstead.game.\(entry.id).details.play")
                        Button("Readiness and save history", action: onShowReadiness)
                            .accessibilityIdentifier("playstead.game.\(entry.id).details.readiness")
                    Button("Correct metadata") { showsMetadataCorrection = true }
                        .accessibilityIdentifier("playstead.game.\(entry.id).metadata-correction.open")
                        Text(titleSource)
                            .font(.psLabel)
                            .foregroundStyle(DesignTokens.textMuted)
                            .accessibilityIdentifier("playstead.game.\(entry.id).title.source")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("playstead.game.\(entry.id).details.identity")

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("About this game").font(.psHeading)
                    if let description = metadata?.description, !description.isEmpty {
                        Text(description)
                            .font(.psBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("playstead.game.\(entry.id).description")
                    } else {
                        Text("No description yet.")
                            .font(.psBody)
                            .foregroundStyle(DesignTokens.textMuted)
                            .accessibilityIdentifier("playstead.game.\(entry.id).description")
                    }
                    Text(descriptionSource)
                        .font(.psLabel)
                        .foregroundStyle(DesignTokens.textMuted)
                        .accessibilityIdentifier("playstead.game.\(entry.id).description.source")
                }

                representativeScreenshot

                HStack {
                    Spacer()
                    Button("Close") { dismissAction() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("playstead.game.\(entry.id).details.close")
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("playstead.game.\(entry.id).details")
        .frame(minWidth: 640, minHeight: 500)
        .background(DesignTokens.background)
        .sheet(isPresented: $showsGallery, onDismiss: {
            galleryTriggerFocused = true
        }) {
            ArtworkGalleryView(
                assetSetID: entry.id,
                gameTitle: title,
                screenshots: screenshots,
                close: { showsGallery = false }
            )
            .environment(environment)
        }
        .sheet(isPresented: $showsMetadataCorrection) {
#if UI_TESTING
            MetadataCorrectionView(entry: entry, fixture: environment.uiTestingMetadataFixture?.correction)
                .id(environment.uiTestingMetadataFixture?.identity)
                .environment(environment)
#else
            MetadataCorrectionView(entry: entry).environment(environment)
#endif
        }
        .onExitCommand { dismissAction() }
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    private var descriptionSource: String {
        let source = metadata?.fieldSources["description"]
        if source?.stringValue == "user" { return "Description written for this private library" }
        if case .object(let fields)? = source, let provider = fields["provider"]?.stringValue {
            return "Description source: \(provider)"
        }
        if case .object(let fields)? = source, fields["source"]?.stringValue == "user" {
            return "Description written for this private library"
        }
        return "Description source unavailable"
    }

    private var titleSource: String {
        let source = metadata?.fieldSources["title"]
        let isUserSource: Bool
        if source?.stringValue == "user" { isUserSource = true }
        else if case .object(let fields)? = source { isUserSource = fields["source"]?.stringValue == "user" }
        else { isUserSource = false }
        if isUserSource {
            return "Title source: your private library"
        }
        if case .object(let fields)? = source,
           let provider = fields["provider"]?.stringValue {
            return "Title source: \(provider)"
        }
        return "Title from the imported filename"
    }

    @ViewBuilder
    private var representativeScreenshot: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Game screenshot").font(.psHeading)
            if let screenshot = screenshots.first {
                ArtworkThumbnailView(
                    assetSetID: entry.id,
                    systemID: entry.system,
                    reference: screenshot,
                    frameSize: CGSize(width: 640, height: 360)
                )
                .accessibilityIdentifier("playstead.game.\(entry.id).screenshot.featured")
                Text("Source: \(screenshot.source)")
                    .font(.psLabel)
                    .accessibilityIdentifier("playstead.game.\(entry.id).screenshot.source")
                if let attribution = screenshot.attribution {
                    Text(attribution).font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                }
                if let rights = screenshot.rights {
                    Text(rights).font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                }
                if !screenshot.caption.isEmpty {
                    Text(screenshot.caption).font(.psBody).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No featured game screenshot.")
                    .foregroundStyle(DesignTokens.textMuted)
                    .accessibilityIdentifier("playstead.game.\(entry.id).screenshot.featured")
            }
            Button("View screenshots") { showsGallery = true }
                .focused($galleryTriggerFocused)
                .accessibilityIdentifier("playstead.game.\(entry.id).gallery.open")
        }
    }

}
