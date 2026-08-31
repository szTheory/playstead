import Foundation

/// The six checks `ReadinessEngine.evaluate` always runs, in this
/// declared order — also the tie-break order when two checks share the
/// same severity (see `ReadinessEngine`'s ordering doc comment).
enum ReadinessCheckKind: String, CaseIterable, Equatable, Hashable {
    case gameAssets
    case cacheVerification
    case emulator
    case bios
    case controllerAndInput
    case saveDirectory
}

enum ReadinessOutcome: Equatable {
    case ready
    case warning(String)
    case blocked(String)

    var isBlocking: Bool {
        if case .blocked = self { return true }
        return false
    }
}

/// One check's result: a kind, an outcome, a plainly worded finding, and
/// — for anything blocking — the `Remedy` the user can act on.
struct ReadinessCheck: Equatable {
    let kind: ReadinessCheckKind
    let outcome: ReadinessOutcome
    let finding: String
    let remedy: Remedy?
}

/// One member (sha256, expected byte size) `ReadinessEngine` checks for
/// presence and integrity — the plan's own required-member shape, named
/// so call sites don't pass anonymous tuples.
struct RequiredMember: Equatable {
    let sha256: String
    let size: Int
}

/// The full ordered result of one `ReadinessEngine.evaluate` call. Play
/// becomes available only when `isReady` is true — i.e. no check in
/// `checks` is `.blocked`.
struct ReadinessReport: Equatable {
    let checks: [ReadinessCheck]

    var isReady: Bool {
        !checks.contains { $0.outcome.isBlocking }
    }
}
