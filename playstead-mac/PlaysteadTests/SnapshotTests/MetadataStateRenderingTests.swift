import AppKit
import SwiftUI
import XCTest
@testable import Playstead

/// Mounts the shipped metadata controls in AppEnvironment for each declared
/// state fixture. The state names correspond to the plan's per-control matrix.
/// The registered packaged UI selectors own the AX, enabled-action, and
/// interaction contract; this test proves each typed fixture reaches its real
/// production route, produces a nonuniform bitmap, and agrees with the local
/// mirror receipt.
@MainActor
final class MetadataStateRenderingTests: XCTestCase {
    private struct Fixture {
        let surface: String
        let state: String

        var identity: String { "\(surface)/\(state)" }
    }

    private static let fixtures: [Fixture] = [
        Fixture(surface: "provider-consent", state: "disabled-unfilled"),
        Fixture(surface: "provider-consent", state: "loading"),
        Fixture(surface: "provider-consent", state: "rejection-error"),
        Fixture(surface: "provider-consent", state: "incomplete-credentials"),
        Fixture(surface: "provider-consent", state: "changed-terms-partial"),
        Fixture(surface: "provider-consent", state: "overflowing-disclosure"),
        Fixture(surface: "provider-consent", state: "long-exact-query"),
        Fixture(surface: "match-candidates", state: "zero"),
        Fixture(surface: "match-candidates", state: "loading"),
        Fixture(surface: "match-candidates", state: "error"),
        Fixture(surface: "match-candidates", state: "populated"),
        Fixture(surface: "match-candidates", state: "partial"),
        Fixture(surface: "match-candidates", state: "overflowing"),
        Fixture(surface: "match-candidates", state: "one-many"),
        Fixture(surface: "match-candidates", state: "long-title"),
        Fixture(surface: "local-media-form", state: "unfilled"),
        Fixture(surface: "local-media-form", state: "uploading"),
        Fixture(surface: "local-media-form", state: "rejected-error"),
        Fixture(surface: "local-media-form", state: "accepted"),
        Fixture(surface: "local-media-form", state: "partial-fields"),
        Fixture(surface: "local-media-form", state: "overlarge-image"),
        Fixture(surface: "local-media-form", state: "long-field-source"),
        Fixture(surface: "metadata-corrections", state: "unchanged"),
        Fixture(surface: "metadata-corrections", state: "loading"),
        Fixture(surface: "metadata-corrections", state: "failed-submit"),
        Fixture(surface: "metadata-corrections", state: "corrected"),
        Fixture(surface: "metadata-corrections", state: "partial-conflict"),
        Fixture(surface: "metadata-corrections", state: "overflow"),
        Fixture(surface: "metadata-corrections", state: "zero-one-many"),
        Fixture(surface: "metadata-corrections", state: "long-text"),
        Fixture(surface: "delivery-preparation", state: "unselected"),
        Fixture(surface: "delivery-preparation", state: "estimating"),
        Fixture(surface: "delivery-preparation", state: "failed"),
        Fixture(surface: "delivery-preparation", state: "ready"),
        Fixture(surface: "delivery-preparation", state: "partial-canceled"),
        Fixture(surface: "delivery-preparation", state: "overflowing"),
        Fixture(surface: "delivery-preparation", state: "zero-one-many"),
        Fixture(surface: "delivery-preparation", state: "long-title"),
        Fixture(surface: "media-cache-controls", state: "empty"),
        Fixture(surface: "media-cache-controls", state: "reclaiming"),
        Fixture(surface: "media-cache-controls", state: "failed"),
        Fixture(surface: "media-cache-controls", state: "under-budget"),
        Fixture(surface: "media-cache-controls", state: "pinned-expired-partial"),
        Fixture(surface: "media-cache-controls", state: "overflow"),
        Fixture(surface: "media-cache-controls", state: "zero-one-many"),
        Fixture(surface: "media-cache-controls", state: "long-label"),
        Fixture(surface: "metadata-settings-navigation", state: "provider-absent"),
        Fixture(surface: "metadata-settings-navigation", state: "loading"),
        Fixture(surface: "metadata-settings-navigation", state: "error"),
        Fixture(surface: "metadata-settings-navigation", state: "enabled-partial-credentials"),
        Fixture(surface: "metadata-settings-navigation", state: "overflowing"),
        Fixture(surface: "metadata-settings-navigation", state: "zero-one-many-groups"),
        Fixture(surface: "metadata-settings-navigation", state: "long-label")
    ]

    func testAllFiftyThreeMetadataControlFixturesMountAndRender() throws {
        XCTAssertEqual(Self.fixtures.count, 53)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-metadata-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let store = try LocalStore(paths: paths)
        let id = UITestBootstrap.metadataAssetSetID
        let seedEntry = CatalogueEntry(id: id, system: "gb", displayTitle: "Fixture game", tags: [:], members: [])
        try CatalogueStore(localStore: store).upsert(seedEntry)
        let environment = AppEnvironment(uiTestingPaths: paths, localStore: store,
                                         reachability: Reachability(startOnline: false, monitorAutomatically: false),
                                         biosReferences: [])
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        var completed = Set<String>()
        var receipts: [String] = []

        for fixture in Self.fixtures {
            let identity = fixture.identity
            let typedFixture = try UITestBootstrap.metadataFixture(identity)
            XCTAssertEqual(typedFixture.identity, identity)
            try MetadataStore(localStore: store).clearAll()
            try environment.installUITestMetadataFixture(identity: identity)
            let selection = environment.metadataSelection(for: id)
            let settings = typedFixture.settings
            if let fixtureSelection = typedFixture.correctionSelection {
                let mirrored = try XCTUnwrap(selection, "\(identity) installs its typed correction selection in MetadataStore")
                XCTAssertEqual(mirrored.description, fixtureSelection.description)
                XCTAssertEqual(mirrored.selections, fixtureSelection.selections)
                XCTAssertEqual(mirrored.fieldSources, fixtureSelection.fieldSources)
                XCTAssertEqual(mirrored.conflicts, fixtureSelection.conflicts)
            } else {
                XCTAssertNil(selection, "\(identity) has no correction metadata selection in the local mirror")
            }
            let routeGames = settings?.testGames ?? []
            let title = selection?.selections["title"]?.stringValue ?? routeGames.first?.displayTitle ?? "Fixture game"
            let entry = CatalogueEntry(id: id, system: "gb", displayTitle: title, tags: [:], members: [])
            let view: AnyView
            if let correction = typedFixture.correction {
                XCTAssertEqual(correction.fixtureIdentity, identity)
                view = AnyView(MetadataCorrectionView(entry: entry, fixture: correction).environment(environment)
                    .frame(width: 760, height: 620))
            } else {
                let settings = try XCTUnwrap(settings, "\(identity) must provide the shared settings fixture")
                XCTAssertEqual(settings.fixtureIdentity, identity)
                view = AnyView(MetadataSettingsView(games: routeGames, fixture: settings).environment(environment)
                    .frame(width: 900, height: 900))
            }
            let routeGameCount = typedFixture.correction == nil ? routeGames.count : 1
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 900, height: fixture.surface == "metadata-corrections" ? 620 : 900)
            window.contentView = hosting
            window.contentView?.layoutSubtreeIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(hosting.frame.width), pixelsHigh: Int(hosting.frame.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: Int(hosting.frame.width) * 4, bitsPerPixel: 32
            ), "\(identity) must produce a renderable production view")
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.bitmapData, "\(identity) rendered no content")
            XCTAssertGreaterThan(bitmap.pixelsWide * bitmap.pixelsHigh, 0, "\(identity) lost its bounded geometry")
            let colorCount = sampledColorCount(in: bitmap)
            XCTAssertGreaterThan(colorCount, 2, "\(identity) must render nonuniform view content, sampledColors=\(colorCount)")
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let imageAttachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            imageAttachment.name = "metadata-fixture-\(identity.replacingOccurrences(of: "/", with: "-"))"
            imageAttachment.lifetime = .keepAlways
            add(imageAttachment)
            let stateReceipt = fixtureReceipt(fixture, selection: selection,
                                              settings: settings, correction: typedFixture.correction,
                                              routeGameCount: routeGameCount)
            XCTAssertTrue(stateReceipt.hasPrefix(identity + "|"), "\(identity) receipt must identify its exact fixture")
            assertFixtureSemantics(fixture, selection: selection, settings: settings,
                                   routeGameCount: routeGameCount)
            receipts.append("\(stateReceipt)|sampledColors=\(colorCount)")
            if fixture.surface == "metadata-corrections" {
                let correctionSelection = try XCTUnwrap(selection)
                XCTAssertEqual(correctionSelection.fieldSources["title"] != nil,
                               ["corrected", "overflow", "long-text"].contains(fixture.state),
                               "\(identity) must retain fixture-specific title provenance")
                XCTAssertEqual(correctionSelection.conflicts.count, fixture.state == "partial-conflict" ? 1 : 0,
                               "\(identity) receipt must reflect its actual mirror conflict state")
            }
            completed.insert(identity)
        }
        XCTAssertEqual(completed.count, 53)
        XCTAssertEqual(receipts.count, 53)
        XCTAssertEqual(Set(receipts.compactMap { $0.split(separator: "|", maxSplits: 1).first.map(String.init) }).count, 53,
                       "the sanitized receipt must account for every distinct production-route state")
        let receiptAttachment = XCTAttachment(string: receipts.joined(separator: "\n"))
        receiptAttachment.name = "metadata-rendering-fixture-receipt"
        receiptAttachment.lifetime = .keepAlways
        add(receiptAttachment)
        store.connection.close()
    }

    private func fixtureReceipt(
        _ fixture: Fixture,
        selection: MetadataSelection?,
        settings: MetadataSettingsStateFixture?,
        correction: MetadataCorrectionStateFixture?,
        routeGameCount: Int
    ) -> String {
        let mirrorTitleLength = selection?.selections["title"]?.stringValue?.count ?? 0
        let conflictCount = selection?.conflicts.count ?? 0
        guard let settings else {
            let source = stringMember("source", in: selection?.fieldSources["title"]) ?? "none"
            let descriptionSource = stringMember("source", in: selection?.fieldSources["description"]) ?? "none"
            return "\(fixture.identity)|mirrorTitleChars=\(mirrorTitleLength)|titleSource=\(source)|" +
                "descriptionChars=\(selection?.description.count ?? 0)|descriptionSource=\(descriptionSource)|" +
                "formTitleChars=\(correction?.title.count ?? 0)|formDescriptionChars=\(correction?.descriptionText.count ?? 0)|" +
                "submitting=\(correction?.isSubmitting ?? false)|message=\(correction?.message == nil ? "absent" : "present")|" +
                "conflicts=\(conflictCount)"
        }
        return "\(fixture.identity)|mirrorTitleChars=\(mirrorTitleLength)|routeGames=\(routeGameCount)|" +
            "preview=\(settings.preview.map { $0.enabled ? "enabled" : "disabled" } ?? "absent")|" +
            "candidates=\(settings.candidates.count)|selected=\(settings.selectedIDs.count)|" +
            "estimate=\(settings.estimate == nil ? "absent" : "present")|jobs=\(settings.jobs.count)|" +
            "media=\(settings.uploadedMedia.count)|cacheBytes=\(settings.cache?.usedBytes ?? 0)|" +
            "pinned=\(settings.cache?.pinnedItems ?? 0)|expiring=\(settings.cache?.expiringItems ?? 0)|conflicts=\(conflictCount)"
    }

    private func stringMember(_ key: String, in value: JSONValue?) -> String? {
        guard case .object(let object) = value else { return nil }
        return object[key]?.stringValue
    }

    private func assertFixtureSemantics(
        _ fixture: Fixture,
        selection: MetadataSelection?,
        settings: MetadataSettingsStateFixture?,
        routeGameCount: Int
    ) {
        guard let settings else {
            XCTAssertEqual(selection?.conflicts.count, fixture.state == "partial-conflict" ? 1 : 0)
            return
        }
        switch fixture.surface {
        case "provider-consent", "metadata-settings-navigation":
            if fixture.state == "loading" || ["provider-absent", "error"].contains(fixture.state) {
                XCTAssertNil(settings.preview, "\(fixture.identity) has no current preview")
            } else {
                XCTAssertNotNil(settings.preview, "\(fixture.identity) has its typed provider preview")
            }
            if fixture.state == "changed-terms-partial" {
                XCTAssertTrue(settings.needsDisclosureReview)
                XCTAssertEqual(settings.reviewedDisclosureRevision, "terms-4")
                XCTAssertEqual(settings.preview?.disclosureRevision, "terms-5-current")
            }
            if fixture.surface == "metadata-settings-navigation" {
                let expected = fixture.state == "provider-absent" ? 0 :
                    (fixture.state == "zero-one-many-groups" ? 2 : (fixture.state == "overflowing" ? 12 : 1))
                XCTAssertEqual(routeGameCount, expected)
            }
        case "match-candidates":
            let expected = ["zero", "error"].contains(fixture.state) ? 0 :
                (fixture.state == "partial" ? 2 : (fixture.state == "one-many" ? 3 : (fixture.state == "overflowing" ? 8 : 1)))
            XCTAssertEqual(settings.candidates.count, expected)
        case "local-media-form":
            if fixture.state == "uploading" {
                XCTAssertEqual(settings.uploadedMedia.count, 1, "cancel fixture preserves its already accepted original")
            }
            if ["accepted", "partial-fields", "long-field-source"].contains(fixture.state) {
                XCTAssertEqual(settings.uploadedMedia.count, 1)
            }
        case "delivery-preparation":
            if fixture.state == "zero-one-many" {
                XCTAssertEqual(routeGameCount, 3)
                XCTAssertTrue(settings.selectedIDs.isEmpty)
                XCTAssertNil(settings.estimate)
            }
            if fixture.state == "overflowing" { XCTAssertEqual(routeGameCount, 12) }
            if ["ready", "partial-canceled", "overflowing", "long-title"].contains(fixture.state) {
                let games = routeGameCount
                XCTAssertEqual(settings.estimate?.requests, games * 2)
                XCTAssertEqual(settings.estimate?.bytes, games * 64_000)
                XCTAssertEqual(settings.estimate?.storage, games * 32_000)
            }
        case "media-cache-controls":
            if fixture.state == "empty" {
                XCTAssertEqual(settings.cache?.usedBytes, 0)
                XCTAssertEqual(settings.cache?.pinnedItems, 0)
            }
            if fixture.state == "under-budget" {
                XCTAssertEqual(settings.cache?.usedBytes, 1_024)
                XCTAssertEqual(settings.cache?.pinnedItems, 1)
            }
            if fixture.state == "zero-one-many" || fixture.state == "pinned-expired-partial" {
                XCTAssertEqual(settings.cache?.pinnedItems, 2)
                XCTAssertEqual(settings.cache?.expiringItems, 1)
            }
            if fixture.state == "overflow" {
                XCTAssertEqual(settings.cache?.usedBytes, 536_871_424)
                XCTAssertEqual(settings.cache?.pinnedItems, 12)
                XCTAssertEqual(settings.cache?.expiringItems, 8)
            }
        default:
            XCTFail("unmapped metadata fixture surface: \(fixture.surface)")
        }
    }

    private func sampledColorCount(in bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData else { return 0 }
        let stepX = max(1, bitmap.pixelsWide / 64)
        let stepY = max(1, bitmap.pixelsHigh / 64)
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                let offset = y * bitmap.bytesPerRow + x * 4
                let color = UInt32(data[offset]) << 24 |
                    UInt32(data[offset + 1]) << 16 |
                    UInt32(data[offset + 2]) << 8 |
                    UInt32(data[offset + 3])
                colors.insert(color)
                if colors.count > 2 { return colors.count }
            }
        }
        return colors.count
    }

}
