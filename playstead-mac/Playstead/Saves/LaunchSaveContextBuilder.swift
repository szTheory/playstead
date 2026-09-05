import Foundation
import CryptoKit

/// Assembles a `LaunchSaveContext` from already-local facts only:
/// `SaveStore.fetchLine`/`fetchHeads` for the line and its current
/// heads, `CASManager.contains(_:)` for whether each head's bytes are
/// already fetched, and a hash of whatever currently sits on disk at
/// the resolved target path. Performs no I/O in its own initializer —
/// every read happens inside `buildContext`, called once per launch.
struct LaunchSaveContextBuilder {
    let saveStore: SaveStore
    let casManager: CASManager
    /// The pinned adapter's declared save contract, read only for its
    /// `media` table (to derive a medium id for the compatibility
    /// gate below). `nil` when no adapter is installed yet — the gate
    /// is then never attached, matching D-20's "degrade toward
    /// strictness when unknown" posture.
    let saveContract: AdapterSaveContract?
    let systemID: String

    /// `contentKey` is the ROM's own sha256 — the server's
    /// `content_key` identity (D-10), never `assetSetID`, so a future
    /// re-import can never orphan a save. `targetURL` is the resolved
    /// `saves/<assetSetID>/<romBaseName>.sav` artifact path this
    /// launch would read from or write to.
    func buildContext(
        contentKey: String, saveKind: String = "battery", slot: String = "0", targetURL: URL
    ) -> LaunchSaveContext {
        let onDisk = Self.onDiskDigest(at: targetURL)

        guard let line = saveStore.fetchLine(contentKey: contentKey, saveKind: saveKind, slot: slot) else {
            // No save line exists for this asset set yet — a
            // first-ever launch is the normal case, not an error.
            // `heads: []` makes `LaunchSavePlanner.plan` yield a no-op
            // plan on every path (`.fresh` into emptiness, or a silent
            // `.keep` when uncaptured bytes are already on disk).
            return LaunchSaveContext(onDiskDigest: onDisk, heads: [])
        }

        let lineRevisions = saveStore.fetchRevisions(saveLineID: line.id)
        let revisionsByID = Dictionary(uniqueKeysWithValues: lineRevisions.map { ($0.id, $0) })
        let headRows = saveStore.fetchHeads(saveLineID: line.id)

        let heads = headRows.map { row in
            SaveHeadCandidate(
                digest: row.blobSHA256,
                bytesLocal: casManager.contains(row.blobSHA256),
                deviceName: row.originDeviceID ?? "another device",
                lastSavedDescription: Self.relativeDescription(for: row)
            )
        }

        let knownDigests = Set(lineRevisions.map(\.blobSHA256))

        var ancestorDigests: Set<String> = []
        var verdict: SaveCompatibilityGate.Verdict?
        if headRows.count == 1, let onlyHead = headRows.first {
            ancestorDigests = Self.ancestorDigests(ofHead: onlyHead, allRevisionsByID: revisionsByID)
            verdict = compatibilityVerdict(for: onlyHead, contentKey: contentKey, saveKind: saveKind)
        }

        return LaunchSaveContext(
            onDiskDigest: onDisk, heads: heads, ancestorDigests: ancestorDigests,
            knownDigests: knownDigests, compatibilityVerdict: verdict
        )
    }

    // MARK: - Compatibility verdict

    /// Evaluates D-24's binding tuple for the single head under
    /// consideration. There is no independent on-disk binding to
    /// compare against when restoring into emptiness — this Mac's own
    /// expectation for the same `content_key` is, by construction, the
    /// same game — so the target binding is built from the same facts
    /// as the candidate, and `SaveCompatibilityGate.evaluate` (not an
    /// assumption baked in here) is what actually decides. The check
    /// that still meaningfully fires: a revision whose recorded size
    /// does not match any medium the adapter pin declares evaluates as
    /// unbound (`mediumID == nil`) and is hard-blocked (D-24), never
    /// silently restored.
    private func compatibilityVerdict(
        for head: SaveRevisionRow, contentKey: String, saveKind: String
    ) -> SaveCompatibilityGate.Verdict? {
        guard let saveContract else { return nil }
        let mediumID = Self.mediumID(forArtifactBytes: head.sizeBytes, contract: saveContract)
        let provenance = SaveProvenance(
            emulator: head.adapterID ?? "",
            emulatorVersion: head.adapterVersion ?? "",
            coreVersion: nil,
            adapterPinSHA256: "",
            capturedAt: head.recordedAt ?? "",
            deviceID: head.originDeviceID ?? ""
        )
        let binding = SaveBinding(
            systemID: systemID,
            saveKind: saveKind,
            mediumID: mediumID,
            artifactBytes: head.sizeBytes,
            romSHA256: contentKey,
            titleIdentity: nil,
            origin: "emulated",
            provenance: provenance
        )
        let gate = SaveCompatibilityGate(saveContract: saveContract)
        return gate.evaluate(candidate: binding, target: binding)
    }

    private static func mediumID(forArtifactBytes bytes: Int, contract: AdapterSaveContract) -> String? {
        contract.media?.first(where: { $0.bytes == bytes })?.id
    }

    // MARK: - Ancestry

    private static func ancestorDigests(
        ofHead headRow: SaveRevisionRow, allRevisionsByID: [String: SaveRevisionRow]
    ) -> Set<String> {
        var digests: Set<String> = []
        var currentParentID = headRow.parentRevisionID
        while let parentID = currentParentID, let parent = allRevisionsByID[parentID] {
            digests.insert(parent.blobSHA256)
            currentParentID = parent.parentRevisionID
        }
        return digests
    }

    // MARK: - On-disk state

    /// `nil` both when nothing exists at `targetURL` and when it exists
    /// but is zero bytes — both count as "the target is empty" (D-44).
    private static func onDiskDigest(at targetURL: URL) -> String? {
        guard let data = try? Data(contentsOf: targetURL), !data.isEmpty else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativeDescription(for row: SaveRevisionRow) -> String {
        guard let recordedAt = row.recordedAt, let date = ISO8601DateFormatter().date(from: recordedAt) else {
            return "recently"
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
