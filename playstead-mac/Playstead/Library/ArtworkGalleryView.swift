import SwiftUI

struct ArtworkGalleryView: View {
    let assetSetID: String
    let gameTitle: String
    let screenshots: [MetadataArtworkReference]
    let close: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0

    private var selectedScreenshot: MetadataArtworkReference? {
        screenshots.indices.contains(selectedIndex) ? screenshots[selectedIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                Text(gameTitle)
                    .font(.psHeading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Text(Self.countLabel(for: screenshots.count))
                    .accessibilityIdentifier("playstead.game.\(assetSetID).gallery.count")
                Button("Close screenshots", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("playstead.game.\(assetSetID).gallery.close")
            }
            if let screenshot = selectedScreenshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        ArtworkThumbnailView(
                            assetSetID: assetSetID,
                            systemID: "",
                            reference: screenshot,
                            frameSize: ArtworkThumbnailView.galleryImageSize,
                            accessibilityID: "playstead.game.\(assetSetID).gallery.image"
                        )
                        Text("Game screenshot").font(.psLabelEmphasized)
                        Text("Source: \(screenshot.source)").font(.psLabel)
                            .accessibilityIdentifier("playstead.game.\(assetSetID).gallery.source")
                        if let attribution = screenshot.attribution {
                            Text(attribution).font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                        }
                        if let rights = screenshot.rights {
                            Text(rights).font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                        }
                        Text("Available only in this private library. Redistribution rights are not granted.")
                            .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                        Text(screenshot.caption).font(.psBody).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    if screenshots.count > 1 {
                        Button("Previous screenshot") { move(by: -1) }
                            .disabled(selectedIndex == 0)
                        Button("Next screenshot") { move(by: 1) }
                            .disabled(selectedIndex == screenshots.count - 1)
                    }
                    Spacer()
                    Text("\(selectedIndex + 1) of \(screenshots.count)")
                        .accessibilityIdentifier("playstead.game.\(assetSetID).gallery.index")
                }
            } else {
                ContentUnavailableView("No screenshots yet", systemImage: "photo.on.rectangle")
                    .accessibilityIdentifier("playstead.game.\(assetSetID).gallery.empty")
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 760, minHeight: 560)
        .accessibilityIdentifier("playstead.game.\(assetSetID).gallery")
        .onChange(of: environment.controllerHost.liveInputs) { previous, current in
            if Self.shouldCloseForControllerB(previous: previous, current: current) { close() }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: move(by: -1)
            case .right: move(by: 1)
            default: break
            }
        }
        .onExitCommand(perform: close)
#if UI_TESTING
        .safeAreaInset(edge: .bottom) {
            if let driver = environment.uiTestControllerInputDriver {
                HStack {
                    Button("Press B") { driver.pressB() }
                        .accessibilityIdentifier("playstead.harness.controller.back")
                    Button("Release B") { driver.releaseB() }
                        .accessibilityIdentifier("playstead.harness.controller.back-release")
                }
            }
        }
#endif
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    static func countLabel(for count: Int) -> String {
        switch count {
        case 0: "0 screenshots"
        case 1: "1 screenshot"
        default: "\(count) screenshots"
        }
    }

    static func shouldCloseForControllerB(previous: Set<String>, current: Set<String>) -> Bool {
        previous.contains("buttonB") && !current.contains("buttonB")
    }

    private func move(by offset: Int) {
        let next = selectedIndex + offset
        guard screenshots.indices.contains(next) else { return }
        selectedIndex = next
    }
}
