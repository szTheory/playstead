import Foundation
import os

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
    /// A member declared the sidecar manifest's own filename. Refused
    /// rather than allowed to overwrite the only record of which files in
    /// the launch directory belong to Playstead — a server that could
    /// clobber that record could make the next materialization delete
    /// whatever it named.
    case reservedMemberName(declaredName: String)
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

    private static let logger = Logger(subsystem: "dev.playstead.mac", category: "launch-materializer")

    /// Records which names this materializer wrote on the previous run
    /// for one asset set.
    ///
    /// The launch directory cannot answer, by inspection, the only
    /// question that matters before deleting anything from it: which of
    /// these files did Playstead put here, and which did the *emulator*
    /// author? This sidecar is that answer, which is why it lives beside
    /// the files it describes and is rewritten on every successful
    /// materialization.
    static let manifestFilename = ".playstead-materialized.json"

    /// Materializes every member's cache object into the launch
    /// directory under its original filename (`declaredName`), so the
    /// emulator sees the layout it expects.
    ///
    /// **Only files this materializer itself wrote are ever removed**
    /// (per the manifest above), and only those it is not about to write
    /// again. Cache-derived files remain rebuilt from the CAS, the
    /// verified source of truth; emulator-authored files in the same
    /// directory are left exactly as the player left them.
    ///
    /// That distinction is the whole point, and it was originally
    /// missing: this method used to `removeItem` the entire directory
    /// first, which is correct for cache-derived files and silent data
    /// loss for everything else. mGBA writes save states (`.ss1`–`.ss9`),
    /// screenshots and cheat files next to the ROM — inside this very
    /// directory — so every Play destroyed the player's save states
    /// (WINDOWS #78; battery saves escaped only because the launch
    /// command relocates them via `-C savegamePath` to
    /// `saves/<asset_set_id>/`).
    ///
    /// A launch directory written before the manifest existed has none,
    /// and then nothing is removed at all: a stale member file from an
    /// earlier asset-set composition may linger once. That is the safe
    /// direction to fail — an unreferenced leftover costs disk, a deleted
    /// save state costs the player's progress — and it self-heals, since
    /// this run writes the manifest that the next one reads.
    ///
    /// Every member is validated, and every source object confirmed to
    /// exist, *before* the first byte is removed or copied. A refused
    /// member therefore leaves the directory exactly as it found it,
    /// rather than half-rebuilt.
    func materialize(assetSetID: String, members: [(sha256: String, declaredName: String)]) throws -> MaterializedLaunch {
        let directory = paths.launchDirectory(forAssetSet: assetSetID)
        let fm = FileManager.default

        // Both halves of every destination are server-controlled and
        // both are validated here, not just at ingest (CR-01/CR-02).
        // `declaredName` reaches `appendingPathComponent` verbatim, so a
        // name like `"../../../../evil.txt"` would resolve out of
        // `launch/<asset_set_id>/` and have `copyItem` write
        // attacker-chosen bytes to an attacker-chosen path — with no App
        // Sandbox behind it (see `Playstead.entitlements`).
        var plan: [(name: String, source: URL, destination: URL)] = []
        for member in members {
            let safeName: String
            let source: URL
            do {
                safeName = try PathSafety.validatedFilename(member.declaredName)
                source = try cas.objectURL(for: member.sha256)
            } catch let error as PathSafetyError {
                throw MaterializationError.unsafeMember(declaredName: member.declaredName, reason: error)
            }
            guard safeName != Self.manifestFilename else {
                throw MaterializationError.reservedMemberName(declaredName: member.declaredName)
            }
            guard fm.fileExists(atPath: source.path) else {
                throw MaterializationError.sourceObjectMissing(sha256: member.sha256)
            }
            plan.append((safeName, source, directory.appendingPathComponent(safeName)))
        }

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let previous = Self.readManifest(in: directory)
        let current = Set(plan.map(\.name))
        for stale in previous.subtracting(current) {
            // The manifest is local state, but it was written from
            // server-supplied names, so it is re-validated on the way
            // back out — a tampered manifest must not be able to name a
            // path outside this directory for removal.
            guard PathSafety.isSafeFilename(stale), stale != Self.manifestFilename else { continue }
            try? fm.removeItem(at: directory.appendingPathComponent(stale))
        }

        var files: [URL] = []
        for step in plan {
            // `copyItem` refuses an existing destination, so the prior
            // copy of this same name is replaced explicitly.
            if fm.fileExists(atPath: step.destination.path) {
                try fm.removeItem(at: step.destination)
            }
            try fm.copyItem(at: step.source, to: step.destination)
            files.append(step.destination)
        }

        Self.writeManifest(current, in: directory)
        return MaterializedLaunch(directory: directory, files: files)
    }

    // MARK: - Manifest

    /// The names recorded by the previous materialization, or the empty
    /// set when there is no readable manifest. Every failure mode —
    /// absent, truncated, not JSON, not an array of strings — means "do
    /// not delete anything", which is the safe answer.
    private static func readManifest(in directory: URL) -> Set<String> {
        let url = directory.appendingPathComponent(manifestFilename)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let names = try? JSONDecoder().decode([String].self, from: data) else {
            logger.error("unreadable launch manifest at \(url.lastPathComponent, privacy: .public); removing nothing this run")
            return []
        }
        return Set(names)
    }

    /// Records what this run wrote. A failure here cannot fail a launch
    /// the player has already earned — the cost is that the next run
    /// reads no manifest and leaves a stale file behind, which is
    /// recoverable, whereas refusing to launch is not — but it must not
    /// be silent either.
    private static func writeManifest(_ names: Set<String>, in directory: URL) {
        let url = directory.appendingPathComponent(manifestFilename)
        do {
            let data = try JSONEncoder().encode(names.sorted())
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("could not write launch manifest: \(error.localizedDescription, privacy: .public)")
        }
    }
}
