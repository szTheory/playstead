import Foundation

/// The three exit categories the plan 03-01 spike proved are
/// distinguishable for the pinned emulator. Published so the UI can
/// return to the library and, later, drive save-recovery messaging.
enum AdapterExit: Equatable {
    case clean
    case crashed
    case killed
    /// A termination signature the pin doesn't recognise — surfaced
    /// rather than silently coerced into one of the three known cases.
    case unknown(status: Int32, reason: String)

    static func classify(
        status: Int32,
        reason: Process.TerminationReason,
        against detection: AdapterExitDetection
    ) -> AdapterExit {
        let reasonString: String
        switch reason {
        case .exit: reasonString = "exit"
        case .uncaughtSignal: reasonString = "uncaughtSignal"
        @unknown default: reasonString = "unknown"
        }

        if matches(detection.clean, status: status, reason: reasonString) { return .clean }
        if matches(detection.crash, status: status, reason: reasonString) { return .crashed }
        if matches(detection.killed, status: status, reason: reasonString) { return .killed }
        return .unknown(status: status, reason: reasonString)
    }

    private static func matches(_ signature: AdapterExitSignature, status: Int32, reason: String) -> Bool {
        signature.terminationStatus == status && signature.terminationReason == reason
    }
}
