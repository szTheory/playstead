import AppKit
import CoreGraphics

// CI-only setup for the two existing packaged window geometry cases. This
// script uses the runner's supported public display modes, never a private
// virtual-display API, and refuses to alter a developer's normal desktop.
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_OS"] == "macOS",
      ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "szTheory/playstead" else {
    fputs("test display setup requires the task's hosted Mac runner\n", stderr)
    exit(2)
}

let display = CGMainDisplayID()
let minimumWidth = 1440
let minimumHeight = 1000
func fits(_ bounds: CGRect) -> Bool {
    bounds.width >= CGFloat(minimumWidth) && bounds.height >= CGFloat(minimumHeight)
}
let before = CGDisplayBounds(display)
if !fits(before) {
    let modes = (CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? [])
        .filter { $0.width >= minimumWidth && $0.height >= minimumHeight }
        .sorted { $0.width * $0.height < $1.width * $1.height }
    guard let mode = modes.first else {
        fputs("test display cannot contain the required 1280x800 content case: \(Int(before.width))x\(Int(before.height))\n", stderr)
        exit(1)
    }
    let result = CGDisplaySetDisplayMode(display, mode, nil)
    guard result == .success else {
        fputs("test display mode change failed: \(result.rawValue)\n", stderr)
        exit(1)
    }
}
let after = CGDisplayBounds(display)
guard fits(after) else {
    fputs("test display preflight did not establish the required viewport\n", stderr)
    exit(1)
}
print("test display: \(Int(before.width))x\(Int(before.height)) -> \(Int(after.width))x\(Int(after.height)); 1280x800 content case fits")
