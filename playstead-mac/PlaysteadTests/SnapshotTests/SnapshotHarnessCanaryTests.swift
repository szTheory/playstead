import AppKit
import CoreImage
import SnapshotTesting
import XCTest

final class SnapshotHarnessCanaryTests: XCTestCase {
    private let snapshotName = "wave-0-snapshot-calibration"

    func testIntentionalMismatchProducesReviewableTriplet() throws {
        let output = try outputDirectory()
        let reference = image(pixel: NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        let mutation = image(pixel: NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.2, alpha: 1))

        XCTAssertNotNil(
            verifySnapshot(
                of: reference,
                as: .image(precision: 1, perceptualPrecision: 1),
                named: snapshotName,
                record: .all,
                snapshotDirectory: output.path,
                testName: "snapshot-harness-canary"
            ),
            "record mode must report its ordinary assertion instead of crashing"
        )
        let mismatch = verifySnapshot(
            of: mutation,
            as: .image(precision: 1, perceptualPrecision: 1),
            named: snapshotName,
            record: .never,
            snapshotDirectory: output.path,
            testName: "snapshot-harness-canary"
        )

        XCTAssertNotNil(mismatch, "a meaningful mutation must produce an ordinary mismatch")
        try writeTriplet(reference: reference, actual: mutation, to: output)
        for name in ["reference.png", "actual.png", "diff.png"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path))
        }
    }

    func testMeaningfulMutationFailsAndCalibratedNoisePasses() throws {
        let output = try outputDirectory()
        // `NSBitmapImageRep` is calibrated RGB. Supplying grayscale-space
        // colors can yield transparent pixels on macOS 26, making distinct
        // inputs compare equal. Keep all calibration fixtures in the
        // representation's explicit color space.
        let reference = image(pixel: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        let mutation = image(pixel: NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        let calibratedNoise = image(pixel: NSColor(calibratedRed: 0.501, green: 0.501, blue: 0.501, alpha: 1))

        XCTAssertNotNil(
            verifySnapshot(
                of: reference,
                as: .image(precision: 1, perceptualPrecision: 1),
                named: "wave-0-mutation-noise",
                record: .all,
                snapshotDirectory: output.path,
                testName: "snapshot-mutation-noise"
            ),
            "record mode must produce a reviewable assertion"
        )
        XCTAssertNotNil(
            verifySnapshot(
                of: mutation,
                as: .image(precision: 1, perceptualPrecision: 1),
                named: "wave-0-mutation-noise",
                record: .never,
                snapshotDirectory: output.path,
                testName: "snapshot-mutation-noise"
            )
        )
        XCTAssertNil(
            verifySnapshot(
                of: calibratedNoise,
                as: .image(precision: 0.99, perceptualPrecision: 0.99),
                named: "wave-0-mutation-noise",
                record: .never,
                snapshotDirectory: output.path,
                testName: "snapshot-mutation-noise"
            )
        )
    }

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT"], !path.isEmpty else {
            throw XCTSkip("PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT is supplied by the hosted verification wrapper")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func image(pixel color: NSColor) -> NSImage {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        for x in 0..<8 {
            for y in 0..<8 { representation.setColor(color, atX: x, y: y) }
        }
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.addRepresentation(representation)
        return image
    }

    private func writeTriplet(reference: NSImage, actual: NSImage, to directory: URL) throws {
        try png(reference).write(to: directory.appendingPathComponent("reference.png"), options: .atomic)
        try png(actual).write(to: directory.appendingPathComponent("actual.png"), options: .atomic)

        let referenceCI = CIImage(data: png(reference))!
        let actualCI = CIImage(data: png(actual))!
        let difference = actualCI.applyingFilter(
            "CIDifferenceBlendMode",
            parameters: [kCIInputBackgroundImageKey: referenceCI]
        )
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cgImage = context.createCGImage(difference, from: difference.extent) else {
            throw NSError(domain: "SnapshotHarnessCanary", code: 1)
        }
        let diff = NSImage(cgImage: cgImage, size: NSSize(width: 8, height: 8))
        try png(diff).write(to: directory.appendingPathComponent("diff.png"), options: .atomic)
    }

    private func png(_ image: NSImage) -> Data {
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return representation.representation(using: .png, properties: [:])!
    }
}
