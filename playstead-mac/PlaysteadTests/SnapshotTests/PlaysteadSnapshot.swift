import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The only project entry point for rendered image assertions. It fixes
/// locale, calendar, time zone, active state, Dynamic Type, animation,
/// appearance, scale, color space, and the calibrated comparator tolerance.
@MainActor
enum PlaysteadSnapshot {
    static let scale: CGFloat = 2
    static let precision: Float = 0.99
    static let perceptualPrecision: Float = 0.99
    static let locale = Locale(identifier: "en_US_POSIX")
    static let timeZone = TimeZone(secondsFromGMT: 0)!
    static let referenceDate = Date(timeIntervalSince1970: 1_725_148_800)

    static func assertContactSheet<Content: View>(
        _ content: Content,
        named name: String,
        pointSize: CGSize,
        suite: String = "LibraryContractSnapshotTests",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard supportedSuites.contains(suite) else {
            throw SnapshotError.unsupportedSuite
        }
        let sheet = HStack(spacing: 0) {
            fixedEnvironment(content, colorScheme: .light, pointSize: pointSize)
            fixedEnvironment(content, colorScheme: .dark, pointSize: pointSize)
        }
        .frame(width: pointSize.width * 2, height: pointSize.height)

        let image = try render(sheet, pointSize: CGSize(width: pointSize.width * 2, height: pointSize.height))
        try assertNonVacuous(
            image,
            expectedPixels: CGSize(width: pointSize.width * 2 * scale, height: pointSize.height * scale),
            file: file,
            line: line
        )
        try compare(image, named: name, suite: suite, file: file, line: line)
    }

    private static func fixedEnvironment<Content: View>(
        _ content: Content,
        colorScheme: ColorScheme,
        pointSize: CGSize
    ) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return content
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, timeZone)
            .environment(\.controlActiveState, .active)
            .environment(\.colorScheme, colorScheme)
            .dynamicTypeSize(.medium)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .frame(width: pointSize.width, height: pointSize.height, alignment: .topLeading)
            .background(
                colorScheme == .dark
                    ? Color(red: 15.0 / 255, green: 23.0 / 255, blue: 42.0 / 255)
                    : Color.white
            )
    }

    private static func render<Content: View>(_ content: Content, pointSize: CGSize) throws -> NSImage {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: pointSize)
        hostingView.layoutSubtreeIfNeeded()

        let pixelsWide = Int(pointSize.width * scale)
        let pixelsHigh = Int(pointSize.height * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: pixelsWide * 4,
            bitsPerPixel: 32
        ) else {
            throw SnapshotError.couldNotCreateBitmap
        }
        bitmap.size = pointSize
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let source = bitmap.cgImage,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelsWide,
                height: pixelsHigh,
                bitsPerComponent: 8,
                bytesPerRow: pixelsWide * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw SnapshotError.couldNotCreateBitmap
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        guard let normalized = context.makeImage() else { throw SnapshotError.couldNotCreateBitmap }
        let sRGBBitmap = NSBitmapImageRep(cgImage: normalized)
        sRGBBitmap.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(sRGBBitmap)
        return image
    }

    private static func assertNonVacuous(
        _ image: NSImage,
        expectedPixels: CGSize,
        file: StaticString,
        line: UInt
    ) throws {
        guard let representation = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let bytes = representation.bitmapData else {
            throw SnapshotError.couldNotReadBitmap
        }

        XCTAssertEqual(representation.pixelsWide, Int(expectedPixels.width), file: file, line: line)
        XCTAssertEqual(representation.pixelsHigh, Int(expectedPixels.height), file: file, line: line)
        XCTAssertEqual(representation.bitsPerSample, 8, file: file, line: line)
        XCTAssertEqual(representation.colorSpace.colorSpaceModel, .rgb, file: file, line: line)

        let first = (bytes[0], bytes[1], bytes[2], bytes[3])
        var hasOpaquePixel = false
        var hasDifferentPixel = false
        for row in 0..<representation.pixelsHigh {
            let rowStart = row * representation.bytesPerRow
            for column in 0..<representation.pixelsWide {
                let offset = rowStart + column * 4
                hasOpaquePixel = hasOpaquePixel || bytes[offset + 3] > 0
                if bytes[offset] != first.0 || bytes[offset + 1] != first.1 || bytes[offset + 2] != first.2 || bytes[offset + 3] != first.3 {
                    hasDifferentPixel = true
                }
                if hasOpaquePixel && hasDifferentPixel { break }
            }
            if hasOpaquePixel && hasDifferentPixel { break }
        }
        XCTAssertTrue(hasOpaquePixel, "snapshot content bounds must contain a visible pixel", file: file, line: line)
        XCTAssertTrue(hasDifferentPixel, "snapshot must be nonuniform", file: file, line: line)
    }

    private static func compare(
        _ actual: NSImage,
        named name: String,
        suite: String,
        file: StaticString,
        line: UInt
    ) throws {
        let referenceURL = referenceDirectory(suite: suite).appendingPathComponent("\(name).png")
        let recording = ProcessInfo.processInfo.environment["PLAYSTEAD_SNAPSHOT_RECORDING"] == "1"
        let strategy = Diffing<NSImage>.image(precision: precision, perceptualPrecision: perceptualPrecision)

        if recording {
            try FileManager.default.createDirectory(
                at: referenceDirectory(suite: suite),
                withIntermediateDirectories: true
            )
            try strategy.toData(actual).write(to: referenceURL, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            XCTFail("Missing reference image \(referenceURL.lastPathComponent); CI recording is disabled", file: file, line: line)
            return
        }
        let expected = strategy.fromData(try Data(contentsOf: referenceURL))
        guard let (message, attachments) = strategy.diffV2(expected, actual) else { return }

        for attachment in attachments {
            if case let .data(data, name) = attachment {
                let value = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                value.name = name
                value.lifetime = .keepAlways
                XCTContext.runActivity(named: "Snapshot mismatch: \(name)") { $0.add(value) }
            }
        }
        XCTFail(message, file: file, line: line)
    }

    private static let supportedSuites = Set([
        "LibraryContractSnapshotTests",
        "StorageContractSnapshotTests"
    ])

    private static func referenceDirectory(suite: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(suite, isDirectory: true)
    }

    private enum SnapshotError: Error {
        case couldNotCreateBitmap
        case couldNotReadBitmap
        case unsupportedSuite
    }
}
