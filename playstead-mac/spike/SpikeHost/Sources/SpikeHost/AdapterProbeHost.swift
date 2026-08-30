import Foundation

/// Wraps Foundation `Process` for launching an external emulator binary and
/// recording exit events. This is the process-control half of probes 1, 2, 3,
/// 4, and 7 — the shipping adapter host's state machine (Phase 3 plan 03-03+)
/// will key off exactly the `(terminationStatus, terminationReason)` shape
/// recorded here.
final class AdapterProbeHost {
    private let logURL: URL
    private var process: Process?
    private let recordLock = NSLock()
    private var didRecord = false

    init(logURL: URL) {
        self.logURL = logURL
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Launches `executableURL` with `arguments`/`environment` and installs a
    /// terminationHandler that appends one JSONL line per exit event. The
    /// production adapter host relies on this async callback; the CLI probe
    /// driver additionally calls `recordExitIfNeeded(for:)` synchronously
    /// after `waitUntilExit()` since `terminationHandler` fires on an
    /// arbitrary queue that can race a short-lived CLI process's own exit.
    /// `didRecord` deduplicates so exactly one JSONL line is written either way.
    @discardableResult
    func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> Process {
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        if let environment {
            proc.environment = environment
        }

        proc.terminationHandler = { [weak self] finished in
            self?.recordExit(
                statusCode: finished.terminationStatus,
                reason: finished.terminationReason
            )
        }

        try proc.run()
        self.process = proc
        return proc
    }

    /// Synchronously records the exit event for `proc` if the async
    /// terminationHandler has not already done so. Safe to call after
    /// `proc.waitUntilExit()` returns.
    func recordExitIfNeeded(for proc: Process) {
        recordExit(statusCode: proc.terminationStatus, reason: proc.terminationReason)
    }

    /// Requests a clean termination (SIGTERM via Process.terminate()).
    func terminate() {
        process?.terminate()
    }

    /// Forcibly kills the process (SIGKILL) — used for the probe-3/probe-4
    /// `kill -9` scenario. Foundation's `Process` has no direct SIGKILL API,
    /// so this shells out to `kill -9 <pid>` against the recorded pid.
    func forceKill() {
        guard let pid = process?.processIdentifier else { return }
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProc.arguments = ["-9", String(pid)]
        try? killProc.run()
        killProc.waitUntilExit()
    }

    private func recordExit(statusCode: Int32, reason: Process.TerminationReason) {
        recordLock.lock()
        if didRecord {
            recordLock.unlock()
            return
        }
        didRecord = true
        recordLock.unlock()

        let reasonString: String
        switch reason {
        case .exit: reasonString = "exit"
        case .uncaughtSignal: reasonString = "uncaughtSignal"
        @unknown default: reasonString = "unknown"
        }

        let event: [String: Any] = [
            "terminationStatus": statusCode,
            "terminationReason": reasonString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        var line = data
        line.append(contentsOf: [0x0A]) // newline

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            }
        } else {
            try? line.write(to: logURL)
        }
    }
}
