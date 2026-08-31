import Foundation

/// The concrete, executable action a blocking `ReadinessCheck` offers.
/// A blocking result is never shipped without one of these — telling a
/// user something is wrong and leaving them to work out what to do is
/// the failure mode `ReadinessEngine` exists to prevent.
enum RemedyAction: Equatable {
    case downloadMember(sha256: String)
    case installAdapter
    case openBiosDropTarget
    case openInputSettings
    case repairSaveDirectory
}

/// A titled, executable remedy attached to a blocking `ReadinessCheck`.
struct Remedy: Equatable {
    let title: String
    let action: RemedyAction
}
