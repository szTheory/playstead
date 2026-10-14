import AppKit
import Foundation

// This helper runs before the coordinator removes its disposable profile.
// App names and bundle identifiers alone are not process ownership evidence.
func ownedEmulatorExecutable(_ executable: URL, root: URL) -> Bool {
    let expectedRoot = root.appendingPathComponent("profile/emulators").standardizedFileURL
    let candidate = executable.standardizedFileURL
    guard candidate.path.hasPrefix(expectedRoot.path + "/"),
          candidate.lastPathComponent == "mGBA",
          candidate.deletingLastPathComponent().lastPathComponent == "MacOS",
          candidate.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents",
          candidate.resolvingSymlinksInPath() == candidate,
          FileManager.default.fileExists(atPath: candidate.path) else { return false }
    return true
}

#if !CLEANUP_TESTING
guard CommandLine.arguments.count == 2 else { exit(77) }
let suppliedRoot = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let root = suppliedRoot.resolvingSymlinksInPath()
guard root.lastPathComponent.hasPrefix("playstead-recovery-e2e."),
      let attributes = try? FileManager.default.attributesOfItem(atPath: root.path),
      attributes[.type] as? FileAttributeType == .typeDirectory,
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { exit(77) }

var refused = false
for application in NSWorkspace.shared.runningApplications {
    guard let executable = application.executableURL?.resolvingSymlinksInPath(),
          ownedEmulatorExecutable(executable, root: root) else { continue }
    let expectedBundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func stillOwned() -> Bool {
        guard !application.isTerminated,
              let current = NSRunningApplication(processIdentifier: application.processIdentifier),
              current.launchDate == application.launchDate,
              current.executableURL?.resolvingSymlinksInPath() == executable,
              current.bundleURL?.resolvingSymlinksInPath() == expectedBundle else { return false }
        return ownedEmulatorExecutable(executable, root: root)
    }
    guard stillOwned() else { refused = true; continue }
    _ = application.terminate()
    let deadline = Date().addingTimeInterval(8)
    while !application.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    if !application.isTerminated && stillOwned() {
        // Abort cleanup is never evidence of a clean save flush.
        _ = application.forceTerminate()
        let forcedDeadline = Date().addingTimeInterval(2)
        while !application.isTerminated && Date() < forcedDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
    if !application.isTerminated { refused = true }
}
exit(refused ? 77 : 0)
#endif
