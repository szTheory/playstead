import AppKit
import CoreGraphics
import CryptoKit
import ImageIO
import SwiftUI
import XCTest
@testable import Playstead

@MainActor
final class ArtworkContractSnapshotTests: XCTestCase {
    private static let stateIdentities: [(String, String)] = [
        ("artwork-card", "empty"), ("artwork-card", "loading"), ("artwork-card", "error"),
        ("artwork-card", "populated"), ("artwork-card", "partial"), ("artwork-card", "overflow"),
        ("artwork-card", "zero-one-many"), ("artwork-card", "long-text"),
        ("game-title", "empty"), ("game-title", "loading"), ("game-title", "error"),
        ("game-title", "populated"), ("game-title", "partial"), ("game-title", "overflow"),
        ("game-title", "zero-one-many"), ("game-title", "long-text"),
        ("game-detail", "empty"), ("game-detail", "loading"), ("game-detail", "error"),
        ("game-detail", "populated"), ("game-detail", "overflow"), ("game-detail", "long-text"),
        ("description", "overflow"), ("description", "long-text"),
        ("representative-screenshot", "empty"), ("representative-screenshot", "loading"),
        ("representative-screenshot", "error"), ("representative-screenshot", "populated"),
        ("representative-screenshot", "overflow"), ("representative-screenshot", "long-text"),
        ("screenshot-gallery", "empty"), ("screenshot-gallery", "loading"),
        ("screenshot-gallery", "error"), ("screenshot-gallery", "populated"),
        ("screenshot-gallery", "partial"), ("screenshot-gallery", "overflow"),
        ("screenshot-gallery", "zero-one-many"), ("screenshot-gallery", "long-text")
    ]

    func testArtworkSlotsPreserveTheLockedCardListAndDestinationGeometry() {
        XCTAssertEqual(DesignTokens.CardGeometry.width, 280)
        XCTAssertEqual(DesignTokens.CardGeometry.height, 224)
        XCTAssertEqual(ArtworkThumbnailView.cardSlotSize, CGSize(width: 44, height: 44))
        XCTAssertEqual(ArtworkThumbnailView.compactSlotSize, CGSize(width: 40, height: 40))
        XCTAssertEqual(ArtworkThumbnailView.detailCoverSize, CGSize(width: 240, height: 320))
        XCTAssertEqual(ArtworkThumbnailView.galleryImageSize, CGSize(width: 720, height: 480))
        XCTAssertEqual(DesignTokens.InteractiveTarget.minimum, 44)
    }

    func testOnlyDigestBoundSelectedMediaCanBecomeGalleryArtwork() async throws {
        let ids = (0..<10).map { String(format: "00000000-0000-7000-8000-%012d", $0 + 1) }
        let references = ids.map { mediaID in
            JSONValue.object([
                "media_id": .string(mediaID),
                "sha256": .string(String(repeating: "a", count: 64)),
                "size_bytes": .int(512),
                "caption": .string(String(repeating: "Game screenshot caption ", count: 20)),
                "aspect_ratio": .number(16.0 / 9.0)
            ])
        }
        let selection = MetadataSelection(
            version: 1,
            type: "description",
            assetSetID: "00000000-0000-7000-8000-000000000097",
            description: "Private description",
            revision: 2,
            deletedAt: nil,
            selections: [
                "cover": references[0],
                "screenshots": .array(references)
            ],
            fieldSources: [
                "cover": .object(["source": .string("user"), "attribution": .string("Added to this private library")]),
                "screenshots": .object(["source": .string("user")])
            ]
        )

        XCTAssertEqual(selection.selectedCover?.role, "Game cover")
        XCTAssertEqual(selection.selectedCover?.source, "user")
        XCTAssertEqual(selection.selectedCover?.aspectRatio ?? 0, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(selection.selectedScreenshots.count, 8)
        XCTAssertTrue(selection.selectedScreenshots.allSatisfy { $0.role == "Game screenshot" })
        XCTAssertEqual(selection.selectedScreenshots[0].caption.count, 480)
        XCTAssertTrue(selection.selectedCover?.expiryPolicyIsValid == true,
                      "private-library uploads without provider rights expiry remain usable")
        XCTAssertNil(selection.selectedCover?.expiresAt)
        XCTAssertEqual(ArtworkGalleryView.countLabel(for: 0), "0 screenshots")
        XCTAssertEqual(ArtworkGalleryView.countLabel(for: 1), "1 screenshot")
        XCTAssertEqual(ArtworkGalleryView.countLabel(for: 8), "8 screenshots")
        XCTAssertTrue(ArtworkGalleryView.shouldCloseForControllerB(previous: ["buttonB"], current: []))
        XCTAssertFalse(ArtworkGalleryView.shouldCloseForControllerB(previous: [], current: ["buttonB"]))
        XCTAssertTrue(ArtworkGalleryView.shouldCloseForControllerB(previous: ["buttonB"], current: []))
        XCTAssertFalse(ArtworkGalleryView.shouldCloseForControllerB(previous: [], current: ["buttonB"]))

        let providerReferenceWithoutAuthorizedBytes = JSONValue.object([
            "image_id": .string("provider-image-123"),
            "size": .string("cover_big")
        ])
        XCTAssertNil(MetadataArtworkReference(value: providerReferenceWithoutAuthorizedBytes, role: "Game cover"),
                     "a provider URL or image ID alone is not an authorized cached selection")

        let providerAsset = JSONValue.object([
            "media_id": .string(ids[0]), "sha256": .string(String(repeating: "a", count: 64)), "size_bytes": .int(512),
            "license_expires_at": .string("2031-01-01T00:00:00Z")
        ])
        let providerSelection = MetadataSelection(
            version: 1, type: "description", assetSetID: selection.assetSetID, description: "", revision: 1,
            deletedAt: nil, selections: ["cover": providerAsset],
            fieldSources: ["cover": .object([
                "source": .string("provider"), "provider": .string("IGDB"),
                "evidence_id": .string("provider-evidence")
            ])],
            evidence: ["provider-evidence": .object([
                "cache_expires_at": .string("2030-06-01T00:00:00Z"),
                "expires_at": .string("2030-09-01T00:00:00Z")
            ])]
        )
        let providerReference = try XCTUnwrap(providerSelection.selectedCover)
        XCTAssertTrue(providerReference.expiryPolicyIsValid)
        XCTAssertEqual(providerReference.expiresAt, ISO8601DateFormatter().date(from: "2030-06-01T00:00:00Z"),
                       "the earliest cache, license, and evidence expiry governs selected provider artwork")

        let noExpirySource: JSONValue = .object(["source": .string("provider"), "provider": .string("IGDB")])
        XCTAssertFalse(MetadataArtworkReference(value: references[0], role: "Game cover", sourceValue: noExpirySource)?.expiryPolicyIsValid ?? true,
                       "provider media without a verifiable expiry must fail closed")
        let malformedSource: JSONValue = .object([
            "source": .string("provider"), "provider": .string("IGDB"), "license_expires_at": .string("not-a-date")
        ])
        XCTAssertFalse(MetadataArtworkReference(value: references[0], role: "Game cover", sourceValue: malformedSource)?.expiryPolicyIsValid ?? true,
                       "malformed rights deadlines must not be treated as non-expiring")
        try await verifyDisplayedArtworkExpires()
    }

    private func verifyDisplayedArtworkExpires() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("playstead-artwork-expiry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = try LocalStore(paths: paths)
        defer { store.connection.close() }
        let png = try Self.fixturePNG()
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let mediaID = "00000000-0000-7000-8000-000000000098"
        let expiry = Date().addingTimeInterval(3)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reference = try XCTUnwrap(MetadataArtworkReference(
            value: .object(["media_id": .string(mediaID), "sha256": .string(digest), "size_bytes": .int(png.count)]),
            role: "Game cover", sourceValue: .object([
                "source": .string("provider"), "provider": .string("IGDB"),
                "expires_at": .string(formatter.string(from: expiry))
            ])
        ))
        let cache = MetadataMediaCache(root: paths.metadataMedia, localStore: store)
        _ = try await cache.store(png, mediaID: mediaID, expectedSHA256: digest, expiresAt: expiry)
        let environment = AppEnvironment(
            uiTestingPaths: paths, localStore: store,
            reachability: Reachability(startOnline: false, monitorAutomatically: false), biosReferences: []
        )
        let host = NSHostingView(rootView: ArtworkThumbnailView(
            assetSetID: "00000000-0000-7000-8000-000000000097", systemID: "gb", reference: reference
        ).environment(environment))
        host.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        func redPixels() throws -> Int {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 176, bitsPerPixel: 32
            ))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return (4..<40).reduce(0) { count, x in
                count + (4..<40).filter { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.redComponent > 0.7 && color.greenComponent < 0.4 && color.blueComponent < 0.4
                }.count
            }
        }
        for _ in 0..<50 {
            if try redPixels() > 800 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(try redPixels(), 800, "the production offline thumbnail must display the authored cached red image before expiry")
        try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow) + 0.15))
        for _ in 0..<50 {
            if try redPixels() < 100 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertLessThan(try redPixels(), 100, "the mounted production thumbnail must remove already-loaded artwork when its rights expire")

        // A transport can finish with an ordinary error after its view task
        // was canceled. That old result must not overwrite the new selection.
        let fixtureURL = root.appendingPathComponent("replacement.png")
        try png.write(to: fixtureURL)
        var paused: CheckedContinuation<URL, Error>?
        var fetchCount = 0
        environment.uiTestingMetadataMediaFetchOverride = {
            fetchCount += 1
            if fetchCount == 1 {
                return try await withCheckedThrowingContinuation { paused = $0 }
            }
            return fixtureURL
        }
        func privateReference(_ id: String) throws -> MetadataArtworkReference {
            try XCTUnwrap(MetadataArtworkReference(
                value: .object(["media_id": .string(id), "sha256": .string(digest), "size_bytes": .int(png.count)]),
                role: "Game cover", sourceValue: .object(["source": .string("user")])
            ))
        }
        host.rootView = ArtworkThumbnailView(
            assetSetID: "00000000-0000-7000-8000-000000000097", systemID: "gb",
            reference: try privateReference("00000000-0000-7000-8000-000000000099")
        ).environment(environment)
        for _ in 0..<50 where paused == nil {
            _ = try redPixels()
            try await Task.sleep(for: .milliseconds(20))
        }
        let oldFetch = try XCTUnwrap(paused, "the old artwork request must be paused before changing selection")
        host.rootView = ArtworkThumbnailView(
            assetSetID: "00000000-0000-7000-8000-000000000097", systemID: "gb",
            reference: try privateReference("00000000-0000-7000-8000-000000000096")
        ).environment(environment)
        for _ in 0..<50 {
            if try redPixels() > 800 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(try redPixels(), 800, "the replacement selection must load before releasing the canceled request")
        oldFetch.resume(throwing: URLError(.badServerResponse))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(try redPixels(), 800, "a canceled request's late ordinary error must preserve the replacement artwork")
        environment.uiTestingMetadataMediaFetchOverride = nil
    }

    func testProductionGameDetailsRenderFromTheLocalMetadataMirror() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-artwork-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = try LocalStore(paths: paths)
        let entry = CatalogueEntry(
            id: "00000000-0000-7000-8000-000000000097",
            system: "gb",
            displayTitle: "A very long game title used to check the detail hierarchy",
            tags: [:],
            members: []
        )
        try CatalogueStore(localStore: store).upsert(entry)
        try MetadataStore(localStore: store).upsert(MetadataSelection(
            version: 1,
            type: "description",
            assetSetID: entry.id,
            description: "A long description remains readable in the bounded details destination. " + String(repeating: "The game description wraps. ", count: 20),
            revision: 1,
            deletedAt: nil,
            selections: [
                "title": .string("Owner-selected display title"),
                "description": .string("A long description remains readable in the bounded details destination.")
            ],
            fieldSources: [
                "title": .string("user"),
                "description": .object(["source": .string("user")])
            ]
        ))
        let environment = AppEnvironment(
            uiTestingPaths: paths,
            localStore: store,
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
            biosReferences: []
        )
        let rootView = GameDetailView(entry: entry, onPlay: {}, onShowReadiness: {})
            .environment(environment)
            .frame(width: 900, height: 720)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 900, height: 720)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 900,
            pixelsHigh: 720,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 3_600,
            bitsPerPixel: 32
        ))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        XCTAssertNotNil(bitmap.bitmapData)
        XCTAssertEqual(environment.metadataSelection(for: entry.id)?.description.contains("bounded details"), true)
        XCTAssertEqual(environment.displayTitle(for: entry), "Owner-selected display title")
        store.connection.close()
    }

    func testThirtyEightProductionArtworkStateFixturesRender() async throws {
        XCTAssertEqual(Self.stateIdentities.count, 38)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-artwork-matrix-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = try LocalStore(paths: paths)
        let entry = CatalogueEntry(
            id: "00000000-0000-7000-8000-000000000097",
            system: "gb",
            displayTitle: "Filename fallback title",
            tags: [:],
            members: []
        )
        try CatalogueStore(localStore: store).upsert(entry)
        let png = try Self.fixturePNG()
        let mediaID = "00000000-0000-7000-8000-000000000098"
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let cache = MetadataMediaCache(root: paths.metadataMedia, localStore: store)
        _ = try await cache.store(png, mediaID: mediaID, expectedSHA256: digest, pinned: true)
        let environment = AppEnvironment(
            uiTestingPaths: paths,
            localStore: store,
            reachability: Reachability(startOnline: false, monitorAutomatically: false),
            biosReferences: []
        )
        let longCaption = String(repeating: "A selected screenshot caption wraps inside its bounded destination. ", count: 12)
        let reference = JSONValue.object([
            "media_id": .string(mediaID), "sha256": .string(digest),
            "size_bytes": .int(png.count), "caption": .string(longCaption), "aspect_ratio": .number(16.0 / 9.0)
        ])
        var completed: Set<String> = []

        for (surface, state) in Self.stateIdentities {
            let identity = "\(surface)/\(state)"
            let hasMedia = !["empty"].contains(state)
            let stateReference: JSONValue? = {
                guard hasMedia else { return nil }
                guard state == "loading" || state == "error" else { return reference }
                let suffix = state == "loading" ? "000000000099" : "000000000096"
                return .object([
                    "media_id": .string("00000000-0000-7000-8000-\(suffix)"),
                    "sha256": .string(digest), "size_bytes": .int(png.count),
                    "caption": .string(longCaption), "aspect_ratio": .number(16.0 / 9.0)
                ])
            }()
            let screenshotValues: [JSONValue]
            if surface == "screenshot-gallery" && state == "empty" {
                screenshotValues = []
            } else if surface == "screenshot-gallery" && state == "zero-one-many" {
                screenshotValues = Array(repeating: reference, count: 10)
            } else {
                screenshotValues = hasMedia ? [stateReference ?? reference] : []
            }
            let selection = MetadataSelection(
                version: 1, type: "description", assetSetID: entry.id,
                description: state == "empty" ? "" : longCaption,
                revision: completed.count + 1, deletedAt: nil,
                selections: [
                    "title": state == "empty" ? .string("") : .string(state == "long-text" ? String(repeating: "Long game title ", count: 16) : "Selected game title"),
                    "description": .string(state == "empty" ? "" : longCaption),
                    "cover": stateReference ?? .null,
                    "screenshots": .array(screenshotValues)
                ],
                fieldSources: [
                    "title": .string("user"),
                    "description": .object(["source": .string("user")]),
                    "cover": .object(["source": .string("user"), "attribution": .string("Private library selection"), "rights": .string("Private use only")]),
                    "screenshots": .object(["source": .string("user"), "rights": .string("Private use only")])
                ]
            )
            try MetadataStore(localStore: store).upsert(selection)
            var loadingFetch: CheckedContinuation<URL, Error>?
            var errorFetchStarted = false
            if state == "loading" {
                environment.uiTestingMetadataMediaFetchOverride = {
                    try await withCheckedThrowingContinuation { loadingFetch = $0 }
                }
            } else if state == "error" {
                environment.uiTestingMetadataMediaFetchOverride = {
                    errorFetchStarted = true
                    throw URLError(.cannotConnectToHost)
                }
            } else {
                environment.uiTestingMetadataMediaFetchOverride = nil
            }
            if surface == "game-title" && state == "empty" {
                XCTAssertEqual(environment.displayTitle(for: entry), "Filename fallback title")
            }
            if surface == "screenshot-gallery" {
                let expectedCount = state == "empty" ? 0 : (state == "zero-one-many" ? 8 : 1)
                XCTAssertEqual(selection.selectedScreenshots.count, expectedCount, "\(identity) must expose its selected still count")
            }
            let view: AnyView
            if surface == "artwork-card" || surface == "game-title" {
                view = AnyView(GameRowView(
                    entry: entry, presentation: .card,
                    onOpenDetails: { _ in }
                ).environment(environment).frame(width: 280, height: 224))
            } else if surface == "screenshot-gallery" {
                view = AnyView(ArtworkGalleryView(
                    assetSetID: entry.id,
                    gameTitle: environment.displayTitle(for: entry),
                    screenshots: selection.selectedScreenshots,
                    close: {}
                ).environment(environment).frame(width: 900, height: 720))
            } else {
                view = AnyView(GameDetailView(entry: entry, onPlay: {}, onShowReadiness: {})
                    .environment(environment).frame(width: 900, height: 720))
            }
            let hostingView = NSHostingView(rootView: view)
            let isCard = surface == "artwork-card" || surface == "game-title"
            hostingView.frame = CGRect(x: 0, y: 0, width: isCard ? 280 : 900, height: isCard ? 224 : 720)
            hostingView.layoutSubtreeIfNeeded()
            if state == "loading" {
                for _ in 0..<40 where loadingFetch == nil { await Task.yield() }
                XCTAssertNotNil(loadingFetch, "\(identity) must enter the real asynchronous artwork fetch path")
            } else if state == "error" {
                for _ in 0..<40 { await Task.yield() }
                XCTAssertTrue(errorFetchStarted, "\(identity) must use the failed local fetch path")
            }
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(hostingView.frame.width), pixelsHigh: Int(hostingView.frame.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: Int(hostingView.frame.width) * 4, bitsPerPixel: 32
            ))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.bitmapData, "\(identity) did not produce a rendered capture")
            XCTAssertGreaterThan(bitmap.pixelsWide * bitmap.pixelsHigh, 0, "\(identity) lost its bounded render geometry")
            let visibleSamples = stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 8)).flatMap { x in
                stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 8)).compactMap { y in bitmap.colorAt(x: x, y: y) }
            }
            XCTAssertGreaterThan(visibleSamples.count, 0, "\(identity) rendered no visible pixels")
            if isCard {
                XCTAssertEqual(hostingView.frame.width, 280, "\(identity) must retain the fixed card width")
                XCTAssertEqual(hostingView.frame.height, 224, "\(identity) must retain the fixed card height")
            }
            if state == "loading" { loadingFetch?.resume(throwing: CancellationError()) }
            completed.insert(identity)
        }
        XCTAssertEqual(completed.count, 38, "every mapped state identity must mount a production view")
        store.connection.close()
    }

    private static func fixturePNG() throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

}
