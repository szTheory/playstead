import Foundation

/// One member materialized into a launch directory: where it landed and
/// which cache object it came from.
struct MaterializedLaunch {
    let directory: URL
    let files: [URL]
}

enum MaterializationError: Error, Equatable {
    case sourceObjectMissing(sha256: String)
    /// A member's server-declared filename was not a safe bare filename,
    /// or its digest was not a well-formed hex digest (CR-01/CR-02).
    /// Launch is refused outright rather than materializing a sanitized
    /// guess at what the server meant.
    case unsafeMember(declaredName: String, reason: PathSafetyError)
}

/// Builds `launch/<asset_set_id>/` and populates it from cache objects
/// using `FileManager.copyItem(at:to:)`, which performs an APFS clone
/// when source and destination are on the same volume and falls back to
/// a full copy otherwise.
///
/// Per D-20 this must never create a hard link: an emulator writing
/// through a hard link would write through into the verified cache
/// object and destroy the custody guarantee. `copyItem` never produces
/// a hard link on APFS — it clones (copy-on-write) or fully copies —
/// which is exactly the isolation this needs.
struct LaunchMaterializer {
    let paths: AppPaths
    let cas: CASManager

    /// Materializes every member's cache object into a fresh launch
    /// directory named by its original filename (`declaredName`), so
    /// the emulator sees the layout it expects. Any file left over from
    /// a previous materialization of the same asset set is removed
    /// first — the launch directory is always rebuilt from the CAS, the
    /// verified source of truth.
    func materialize(assetSetID: String, members: [(sha256: String, declaredName: String)]) throws -> MaterializedLaunch {
        let directory = paths.launchDirectory(forAssetSet: assetSetID)
        let fm = FileManager.default

        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [URL] = []
        for member in members {
            // Both halves of the destination are server-controlled and
            // both are validated here, not just at ingest (CR-01/CR-02).
            // `declaredName` reaches `appendingPathComponent` verbatim, so
            // a name like `"../../../../evil.txt"` would resolve out of
            // `launch/<asset_set_id>/` and have `copyItem` write
            // attacker-chosen bytes to an attacker-chosen path — with no
            // App Sandbox behind it (see `Playstead.entitlements`).
            let safeName: String
            let source: URL
            do {
                safeName = try PathSafety.validatedFilename(member.declaredName)
                source = try cas.objectURL(for: member.sha256)
            } catch let error as PathSafetyError {
                throw MaterializationError.unsafeMember(declaredName: member.declaredName, reason: error)
            }

            guard fm.fileExists(atPath: source.path) else {
                throw MaterializationError.sourceObjectMissing(sha256: member.sha256)
            }
            let destination = directory.appendingPathComponent(safeName)
            try fm.copyItem(at: source, to: destination)
            files.append(destination)
        }

        return MaterializedLaunch(directory: directory, files: files)
    }
}
