#if UI_TESTING
import Foundation

/// Fail-closed bridge letting a UI test hand `BiosDropTargetView` one
/// candidate file without an `NSOpenPanel`, which no headless XCUITest
/// can drive.
///
/// This exists for exactly the reason `UITestBootstrap`'s own env-var
/// seams exist: the BIOS surface's only two inputs are a drag session
/// and a modal file panel, and an automated check can drive neither. It
/// is compiled out entirely outside the `UI_TESTING` configuration, so
/// no shipped build has this code at all — the same guarantee
/// `DeterministicProfile` relies on.
///
/// The accepted value is a path, so it is validated rather than
/// trusted, matching `UITestBootstrap.ownedURL`/`containedURL`:
///   * it must live under this process's temporary directory,
///   * it must be a regular file,
///   * it must not be a symbolic link.
/// Anything else resolves to `nil`, which the view treats exactly like
/// a cancelled panel. `BiosStore.validateAndAccept` independently
/// re-checks the link and regular-file conditions on whatever it is
/// handed; this is a second gate, not a substitute for that one.
enum UITestBiosCandidate {
    static let pathKey = "PLAYSTEAD_UI_TEST_BIOS_CANDIDATE"

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let raw = environment[pathKey], !raw.isEmpty else { return nil }

        let url = URL(fileURLWithPath: raw).standardizedFileURL
        let temporaryRoot = fileManager.temporaryDirectory.standardizedFileURL

        // Containment by path components, never by string prefix: a
        // prefix test accepts a sibling directory whose name merely
        // starts with the root's name.
        let rootComponents = temporaryRoot.pathComponents
        guard url.pathComponents.count > rootComponents.count,
              Array(url.pathComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }

        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else { return nil }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular
        else { return nil }

        return url
    }
}
#endif
