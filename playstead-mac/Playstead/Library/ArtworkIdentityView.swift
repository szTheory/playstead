import SwiftUI

/// A selected media reference is displayable only when the synced selection
/// names an authenticated, digest-bound cache object. Provider image URLs and
/// title-derived art are never accepted here.
struct MetadataArtworkReference: Identifiable, Equatable {
    let mediaID: String
    let sha256: String
    let size: Int
    let role: String
    let caption: String
    let source: String
    let attribution: String?
    let rights: String?
    let aspectRatio: CGFloat?
    let expiresAt: Date?
    let expiryPolicyIsValid: Bool

    var id: String { mediaID }

    init?(value: JSONValue?, role: String, sourceValue: JSONValue? = nil, evidenceValue: JSONValue? = nil) {
        guard case .object(let fields)? = value,
              let mediaID = (fields["media_id"] ?? fields["id"])?.stringValue,
              UUID(uuidString: mediaID) != nil,
              let sha256 = fields["sha256"]?.stringValue,
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit),
              case .int(let size)? = fields["size_bytes"] ?? fields["size"],
              size > 0, size <= MetadataMediaCache.maxObjectBytes else { return nil }
        self.mediaID = mediaID
        self.sha256 = sha256.lowercased()
        self.size = size
        self.role = role
        self.caption = fields["caption"]?.stringValue ?? ""
        if case .number(let ratio)? = fields["aspect_ratio"], ratio.isFinite, ratio > 0 {
            self.aspectRatio = CGFloat(ratio)
        } else {
            self.aspectRatio = nil
        }
        if case .object(let sourceFields)? = sourceValue {
            let provider = sourceFields["provider"]?.stringValue
            let origin = sourceFields["source"]?.stringValue
            self.source = provider ?? origin ?? "Selected game artwork"
            self.attribution = sourceFields["attribution"]?.stringValue
            self.rights = sourceFields["rights"]?.stringValue ?? sourceFields["rights_statement"]?.stringValue
            let dateFields = [fields, sourceFields, evidenceValue?.objectValue ?? [:]]
            var expiries: [Date] = []
            var malformedExpiry = false
            var sawExpiry = false
            for dateField in dateFields {
                for key in ["expires_at", "cache_expires_at", "license_expires_at"] where dateField[key] != nil {
                    sawExpiry = true
                    guard let value = dateField[key]?.stringValue,
                          let date = Self.parseExpiry(value) else {
                        malformedExpiry = true
                        continue
                    }
                    expiries.append(date)
                }
            }
            self.expiryPolicyIsValid = !malformedExpiry && (origin == "user" || (origin == "provider" && sawExpiry))
            self.expiresAt = expiries.min()
        } else if sourceValue?.stringValue == "user" {
            self.source = "user"
            self.attribution = nil
            self.rights = nil
            self.expiresAt = nil
            self.expiryPolicyIsValid = true
        } else {
            self.source = "Selected game artwork"
            self.attribution = nil
            self.rights = nil
            self.expiresAt = nil
            self.expiryPolicyIsValid = false
        }
    }

    private static func parseExpiry(_ value: String) -> Date? {
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]
        ]
        for options in optionSets {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let values) = self else { return nil }
        return values
    }
}

extension MetadataSelection {
    var selectedCover: MetadataArtworkReference? {
        let source = fieldSources["cover"]
        return MetadataArtworkReference(value: selections["cover"], role: "Game cover", sourceValue: source,
                                        evidenceValue: evidenceValue(for: source))
    }

    var selectedScreenshots: [MetadataArtworkReference] {
        guard case .array(let values)? = selections["screenshots"] else { return [] }
        return Array(values.prefix(8)).compactMap {
            MetadataArtworkReference(value: $0, role: "Game screenshot", sourceValue: fieldSources["screenshots"],
                                     evidenceValue: evidenceValue(for: fieldSources["screenshots"]))
        }
    }

    private func evidenceValue(for source: JSONValue?) -> JSONValue? {
        guard case .object(let values)? = source,
              let id = values["evidence_id"]?.stringValue else { return nil }
        return evidence[id]
    }
}

/// Metadata belongs beside the game's existing identity, leaving row actions
/// and save/readiness state in their established locations.
struct ArtworkIdentityView: View {
    var assetSetID: String? = nil
    let systemID: String
    let description: String?
    var frameSize = ArtworkThumbnailView.cardSlotSize

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ArtworkThumbnailView(
                assetSetID: assetSetID ?? "system-\(systemID)",
                systemID: systemID,
                reference: assetSetID.flatMap { environment.metadataSelection(for: $0)?.selectedCover },
                frameSize: frameSize
            )
            if let description, !description.isEmpty {
                Text(description)
                    .font(.psLabel)
                    .foregroundStyle(DesignTokens.textMuted)
                    .lineLimit(2)
                    .accessibilityIdentifier("playstead.game.description")
            }
        }
    }
}

struct ArtworkThumbnailView: View {
    static let cardSlotSize = CGSize(width: 44, height: 44)
    static let compactSlotSize = CGSize(width: 40, height: 40)
    static let detailCoverSize = CGSize(width: 240, height: 320)
    static let galleryImageSize = CGSize(width: 720, height: 480)

    let assetSetID: String
    let systemID: String
    let reference: MetadataArtworkReference?
    var frameSize = ArtworkThumbnailView.cardSlotSize
    var accessibilityID: String? = nil
    var accessibleLabel: String? = nil

    @Environment(AppEnvironment.self) private var environment
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var failed = false
    @State private var rightsUnavailable = false
    @State private var retry = 0

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading game artwork")
            } else {
                SystemMonogramView(systemID: systemID)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tight))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName). \(accessibilityStatus)")
        .accessibilityValue(accessibilityStatus)
        .accessibilityIdentifier(accessibilityID ?? "playstead.game.\(assetSetID).artwork")
        .overlay(alignment: .bottomTrailing) {
            if failed {
                Button {
                    failed = false
                    retry += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Retry loading game artwork")
                .accessibilityLabel("Retry loading game artwork")
            }
        }
        .task(id: "\(reference?.mediaID ?? "empty")-\(reference?.sha256 ?? "")-\(reference?.size ?? 0)-\(reference?.expiresAt?.timeIntervalSince1970 ?? -1)-\(reference?.expiryPolicyIsValid ?? false)-\(retry)") {
            await loadArtwork()
            await expireArtworkWhenPolicyEnds()
        }
    }

    private var accessibilityStatus: String {
        if isLoading { return "Loading artwork" }
        if rightsUnavailable { return "Artwork unavailable: its rights status cannot be verified or has expired." }
        if failed { return "Artwork could not be loaded. Retry is available." }
        if image != nil { return "Artwork loaded" }
        return "No selected artwork; showing the system monogram"
    }

    private var accessibilityName: String {
        if let accessibleLabel { return accessibleLabel }
        if let reference { return "\(reference.role), \(reference.source)" }
        return "No game artwork"
    }

    @MainActor
    private func loadArtwork() async {
        guard !Task.isCancelled else { return }
        guard let reference else {
            image = nil
            failed = false
            rightsUnavailable = false
            isLoading = false
            return
        }
        guard reference.expiryPolicyIsValid,
              reference.expiresAt.map({ $0 > Date() }) ?? true else {
            image = nil
            failed = false
            rightsUnavailable = true
            isLoading = false
            return
        }
        image = nil
        isLoading = true
        failed = false
        rightsUnavailable = false
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let url = try await environment.fetchMetadataMedia(
                assetSetID: assetSetID,
                mediaID: reference.mediaID,
                sha256: reference.sha256,
                size: reference.size,
                expiresAt: reference.expiresAt,
                pinned: true
            )
            guard !Task.isCancelled else { return }
            guard reference.expiresAt.map({ $0 > Date() }) ?? true else {
                image = nil
                rightsUnavailable = true
                return
            }
            image = NSImage(contentsOf: url)
            failed = image == nil
        } catch is CancellationError {
            return
        } catch MetadataMediaCacheError.expired {
            guard !Task.isCancelled else { return }
            image = nil
            failed = false
            rightsUnavailable = true
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }

    @MainActor
    private func expireArtworkWhenPolicyEnds() async {
        guard let expiry = reference?.expiresAt else { return }
        while expiry > Date() {
            do { try await Task.sleep(for: .seconds(min(expiry.timeIntervalSinceNow, 24 * 60 * 60))) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        image = nil
        failed = false
        rightsUnavailable = true
    }
}
