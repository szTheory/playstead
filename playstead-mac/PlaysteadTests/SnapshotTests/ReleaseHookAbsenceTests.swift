import XCTest
@testable import Playstead

final class ReleaseHookAbsenceTests: XCTestCase {
    private static let forbiddenTokens = [
        "UITestBootstrap",
        "UITestProfileRootView",
        "DeterministicProfile",
        "DeterministicProfileFixture",
        "PLAYSTEAD_UI_TESTING",
        "PLAYSTEAD_UI_TEST_PROFILE",
        "blockExternalIOForUITesting",
        "uiTestingBlocksExternalIO",
        "uiTestingLocalStore"
    ]

    func testScannerRejectsSeededForbiddenHookToken() {
        let seeded = Data("ordinary-prefix PLAYSTEAD_UI_TEST_PROFILE ordinary-suffix".utf8)
        XCTAssertEqual(forbiddenTokens(in: seeded), ["PLAYSTEAD_UI_TEST_PROFILE"])
    }

    func testNonTestingReleaseBinaryAndSymbolsContainNoBootstrapProfileOrEnvironmentKey() throws {
        let binary = try buildNonTestingReleaseBinary()
        let bytes = try Data(contentsOf: binary)
        XCTAssertEqual(forbiddenTokens(in: bytes), [], "Release binary leaked a UI-testing hook")

        let symbols = try toolOutput("/usr/bin/nm", ["-j", binary.path])
        XCTAssertEqual(forbiddenTokens(in: Data(symbols.utf8)), [], "Release symbols leaked a UI-testing hook")
    }

    private func forbiddenTokens(in data: Data) -> [String] {
        Self.forbiddenTokens.filter { data.range(of: Data($0.utf8)) != nil }
    }

    private func buildNonTestingReleaseBinary() throws -> URL {
        let macRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-release-absence-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: derivedData) }

        let result = try toolOutput(
            "/usr/bin/xcodebuild",
            [
                "build",
                "-project", macRoot.appendingPathComponent("Playstead.xcodeproj").path,
                "-scheme", "Playstead",
                "-configuration", "Release",
                "-destination", "platform=macOS",
                "-derivedDataPath", derivedData.path,
                "CODE_SIGNING_ALLOWED=NO",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS="
            ]
        )
        XCTAssertTrue(result.contains("BUILD SUCCEEDED"), "Release build did not report success")

        let binary = derivedData
            .appendingPathComponent("Build/Products/Release/Playstead.app/Contents/MacOS/Playstead")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            XCTFail("Release executable was not produced at the asserted path")
            throw CocoaError(.fileNoSuchFile)
        }
        return binary
    }

    private func toolOutput(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-tool-output-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try output.synchronize()
        let data = try Data(contentsOf: outputURL)
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            XCTFail("\(executable) failed closed with status \(process.terminationStatus):\n\(text.suffix(4_000))")
            throw CocoaError(.executableLoad)
        }
        return text
    }
}

final class IdentityAndFocusPrimitiveTests: XCTestCase {
    func testIdentifierVocabularyIsNamespacedUniqueAndContainsNoSensitiveInputs() {
        let identifiers = AccessibilityIdentifiers.allStaticIdentifiers
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("playstead.") })

        for forbidden in ["Game Title", "/Users/owner", "sha256", "credential", "token", "280x158"] {
            XCTAssertFalse(identifiers.contains { $0.localizedCaseInsensitiveContains(forbidden) })
        }
    }

    func testIdentityVocabularyHasExactSurfaceAndControlNamespaces() {
        XCTAssertEqual(AccessibilityIdentifiers.Surface.library, "playstead.surface.library")
        XCTAssertEqual(AccessibilityIdentifiers.Surface.downloads, "playstead.surface.downloads")
        XCTAssertEqual(AccessibilityIdentifiers.Control.done, "playstead.control.done")
        XCTAssertEqual(AccessibilityIdentifiers.Control.moveUp, "playstead.control.move-up")
        XCTAssertEqual(AccessibilityIdentifiers.Control.moveDown, "playstead.control.move-down")
    }

    func testFocusRingUsesLockedCyanOnlyWhenFocusIsOwned() {
        XCTAssertEqual(PlaysteadFocusRing.colorHex, "#38BDF8")
        XCTAssertEqual(PlaysteadFocusRing.lineWidth, 2)
        XCTAssertEqual(PlaysteadFocusRing.opacity(isFocused: true), 1)
        XCTAssertEqual(PlaysteadFocusRing.opacity(isFocused: false), 0)
    }
}
