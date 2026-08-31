import Foundation

/// One member materialized into a launch directory: where it landed and
/// which cache object it came from.
struct MaterializedLaunch {
    let directory: URL
    let files: [URL]
}

enum MaterializationError: Error, Equatable {
    case sourceObjectMissing(sha256: String)
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
            let source = cas.objectURL(for: member.sha256)
            guard fm.fileExists(atPath: source.path) else {
                throw MaterializationError.sourceObjectMissing(sha256: member.sha256)
            }
            let destination = directory.appendingPathComponent(member.declaredName)
            try fm.copyItem(at: source, to: destination)
            files.append(destination)
        }

        return MaterializedLaunch(directory: directory, files: files)
    }
}
