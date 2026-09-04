import Foundation

/// The concrete, executable action a `ReadinessCheck` offers. Every
/// blocking result is shipped with one of these — telling a user
/// something is wrong and leaving them to work out what to do is the
/// failure mode `ReadinessEngine` exists to prevent. `.reviewSaveVersions`
/// is the one exception that attaches to a non-blocking `.warning`
/// outcome (D-37): the Save row's two-versions case is navigational,
/// never blocked, and still deserves a concrete action.
enum RemedyAction: Equatable {
    case downloadMember(sha256: String)
    case installAdapter
    case openBiosDropTarget
    case openInputSettings
    case repairSaveDirectory
    case reviewSaveVersions
}

/// A titled, executable remedy attached to a blocking `ReadinessCheck`.
struct Remedy: Equatable {
    let title: String
    let action: RemedyAction
}
