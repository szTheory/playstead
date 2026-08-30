import Foundation
import SwiftUI

// MARK: - CLI dispatch
//
// SpikeHost is a throwaway probe harness (see spike/README.md) — NOT the
// shipping client. It is a real SwiftUI app bundle (so Gatekeeper/notarization/
// hardened-runtime probes are meaningful), but every probe is driven by
// subcommands so the probe scripts can automate it end-to-end instead of
// requiring a human to click through a UI. With no arguments it falls through
// to a minimal SwiftUI window so it is still a legitimate double-clickable app.

func outDir() -> URL {
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("out")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func writeJSON(_ object: [String: Any], to url: URL) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
        FileHandle.standardError.write(Data("failed to serialize JSON\n".utf8))
        return
    }
    try? data.write(to: url)
}

func runEnvironmentProbe() {
    func sysctl(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    let productVersion = sysctl("/usr/bin/sw_vers", ["-productVersion"])
    let buildVersion = sysctl("/usr/bin/sw_vers", ["-buildVersion"])

    writeJSON([
        "macos_product_version": productVersion,
        "macos_build_version": buildVersion,
        "recorded_at": ISO8601DateFormatter().string(from: Date())
    ], to: outDir().appendingPathComponent("environment.json"))

    print("environment.json written: \(productVersion) (\(buildVersion))")
}

func runKeychainStore(account: String, secret: String) {
    let status = KeychainProbe.store(account: account, secret: secret)
    print("store OSStatus=\(status)")
    exit(status == errSecSuccess ? 0 : 1)
}

func runKeychainRead(account: String) {
    let (status, value) = KeychainProbe.read(account: account)
    writeJSON([
        "probe": "probe-06",
        "verdict": (status == errSecSuccess && value != nil) ? "pass" : "fail",
        "evidence": [
            "os_status": Int(status),
            "value_read": (value as Any?) ?? NSNull()
        ],
        "notes": "raw OSStatus from SecItemCopyMatching; errSecSuccess=\(errSecSuccess)"
    ], to: outDir().appendingPathComponent("probe-06.json"))
    print("read OSStatus=\(status) value=\(value ?? "<nil>")")
    exit(status == errSecSuccess ? 0 : 1)
}

func runLaunch(executablePath: String, arguments: [String]) {
    let host = AdapterProbeHost(logURL: outDir().appendingPathComponent("exit-events.jsonl"))
    do {
        let proc = try host.launch(executableURL: URL(fileURLWithPath: executablePath), arguments: arguments)
        proc.waitUntilExit()
        host.recordExitIfNeeded(for: proc)
        print("exited status=\(proc.terminationStatus) reason=\(proc.terminationReason.rawValue)")
    } catch {
        FileHandle.standardError.write(Data("launch failed: \(error)\n".utf8))
        exit(1)
    }
}

func runLaunchAndKill(executablePath: String, killAfterSeconds: Double, arguments: [String]) {
    let host = AdapterProbeHost(logURL: outDir().appendingPathComponent("exit-events.jsonl"))
    do {
        let proc = try host.launch(executableURL: URL(fileURLWithPath: executablePath), arguments: arguments)
        Thread.sleep(forTimeInterval: killAfterSeconds)
        host.forceKill()
        proc.waitUntilExit()
        host.recordExitIfNeeded(for: proc)
        print("force-killed after \(killAfterSeconds)s status=\(proc.terminationStatus) reason=\(proc.terminationReason.rawValue)")
    } catch {
        FileHandle.standardError.write(Data("launch failed: \(error)\n".utf8))
        exit(1)
    }
}

func runLaunchAndSegv(executablePath: String, afterSeconds: Double, arguments: [String]) {
    let host = AdapterProbeHost(logURL: outDir().appendingPathComponent("exit-events.jsonl"))
    do {
        let proc = try host.launch(executableURL: URL(fileURLWithPath: executablePath), arguments: arguments)
        Thread.sleep(forTimeInterval: afterSeconds)
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProc.arguments = ["-SEGV", String(proc.processIdentifier)]
        try? killProc.run()
        killProc.waitUntilExit()
        proc.waitUntilExit()
        host.recordExitIfNeeded(for: proc)
        print("SEGV'd after \(afterSeconds)s status=\(proc.terminationStatus) reason=\(proc.terminationReason.rawValue)")
    } catch {
        FileHandle.standardError.write(Data("launch failed: \(error)\n".utf8))
        exit(1)
    }
}

let args = CommandLine.arguments
if args.count > 1 {
    let command = args[1]
    switch command {
    case "environment":
        runEnvironmentProbe()
        exit(0)
    case "keychain-store":
        guard args.count >= 4 else {
            FileHandle.standardError.write(Data("usage: SpikeHost keychain-store <account> <secret>\n".utf8))
            exit(64)
        }
        runKeychainStore(account: args[2], secret: args[3])
    case "keychain-read":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: SpikeHost keychain-read <account>\n".utf8))
            exit(64)
        }
        runKeychainRead(account: args[2])
    case "launch":
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: SpikeHost launch <executable> [args...]\n".utf8))
            exit(64)
        }
        runLaunch(executablePath: args[2], arguments: Array(args.dropFirst(3)))
        exit(0)
    case "launch-and-kill9":
        guard args.count >= 4, let seconds = Double(args[3]) else {
            FileHandle.standardError.write(Data("usage: SpikeHost launch-and-kill9 <executable> <seconds> [args...]\n".utf8))
            exit(64)
        }
        runLaunchAndKill(executablePath: args[2], killAfterSeconds: seconds, arguments: Array(args.dropFirst(4)))
        exit(0)
    case "launch-and-segv":
        guard args.count >= 4, let seconds = Double(args[3]) else {
            FileHandle.standardError.write(Data("usage: SpikeHost launch-and-segv <executable> <seconds> [args...]\n".utf8))
            exit(64)
        }
        runLaunchAndSegv(executablePath: args[2], afterSeconds: seconds, arguments: Array(args.dropFirst(4)))
        exit(0)
    default:
        FileHandle.standardError.write(Data("unknown subcommand: \(command)\n".utf8))
        exit(64)
    }
}

// No subcommand: present a minimal SwiftUI window so this is a legitimate
// double-clickable, windowed macOS app (satisfies the "real app" half of
// probe 1's Gatekeeper/notarization assessment, independent of automation).
struct SpikeHostRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("SpikeHost").font(.title)
            Text("Throwaway D-01 probe harness — not the shipping Playstead client.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(width: 420, height: 200)
    }
}

struct SpikeHostAppMain: App {
    var body: some Scene {
        WindowGroup {
            SpikeHostRootView()
        }
    }
}

SpikeHostAppMain.main()
