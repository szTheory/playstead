import Foundation

/// Installs a real, runnable stand-in for the pinned emulator, which is
/// not available in any test environment.
///
/// **Every stand-in must be ad-hoc re-signed, and that is the whole
/// point of this type.** macOS routes the spawn of a file it recognises
/// as an application bundle's main executable through a security
/// assessment before it lets the child run. A system binary's signature
/// is only valid at its platform path, so a plain `copyItem` of
/// `/bin/echo`, `/bin/sleep` or `/usr/bin/true` fails that assessment —
/// and the failure mode is silent and indistinguishable from slowness:
/// `Process.run()` succeeds, the child is left suspended at
/// `_dyld_start` forever, and `terminationHandler` never fires. The test
/// then times out on an exit expectation and reads as a flaky wait.
///
/// That is exactly what WINDOWS #85 mis-diagnosed as machine load and
/// answered with a larger timeout. The bound was never the problem: a
/// spawn that has not called back in five seconds is not slow, it is
/// stuck, and no constant fixes a process that will never exit.
///
/// `AdapterWiringTests` already carried this re-signing for its own
/// bundle fixture, and its doc comment claimed `PlaySessionTests` did
/// the same — it did not, and neither did `LaunchMutexTests`,
/// `SavePlanExecutorTests` or `PlayPathSaveWiringTests`. Centralising it
/// here is what makes that claim true for every call site instead of
/// true in one place and assumed in five.
enum StandInExecutable {
    /// Raised when the stand-in could not be re-signed. Fatal on
    /// purpose: an unsigned stand-in does not fail, it hangs, so this
    /// refuses up front rather than leaving a test to time out later.
    struct SigningFailure: Error, CustomStringConvertible {
        let status: Int32
        let path: String
        var description: String {
            "ad-hoc codesign of stand-in at \(path) failed with status \(status); "
            + "an unsigned stand-in hangs at _dyld_start instead of exiting"
        }
    }

    /// Copies `source` to `destination`, makes it executable, and ad-hoc
    /// re-signs it so the spawned child actually runs and exits.
    static func install(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: destination.path
        )
        try adHocSign(destination)
    }

    /// Ad-hoc re-signs a file already in place.
    static func adHocSign(_ url: URL) throws {
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", url.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            throw SigningFailure(status: codesign.terminationStatus, path: url.path)
        }
    }
}
