import Foundation

/// Names the specific member that failed readiness, so the UI (and a
/// later remedy vocabulary — plan 03-09) can point at exactly what's
/// wrong rather than a generic "not ready".
struct ReadinessBlocker: Equatable {
    let sha256: String
    let reason: String
}

enum ReadinessResult: Equatable {
    case ready
    case blocked([ReadinessBlocker])
}

/// Gates launch on every required member being verifiably present and
/// intact — CACH-04's contract: **zero network calls anywhere in this
/// path**. Trusts the full hash computed at download-completion time
/// through a cheap size+inode+mtime comparison against the CAS's
/// verify record, falling back to a full re-hash only when that cheap
/// check disagrees (still entirely local).
struct PreflightChecker {
    let cas: CASManager

    /// `requiredMembers` — sha256, expected size — for the asset set's
    /// required members only, per CACH-04 (optional members never block
    /// launch readiness).
    func check(requiredMembers: [(sha256: String, size: Int)]) -> ReadinessResult {
        var blockers: [ReadinessBlocker] = []

        for member in requiredMembers {
            let objectURL = cas.objectURL(for: member.sha256)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: objectURL.path) else {
                blockers.append(ReadinessBlocker(sha256: member.sha256, reason: "missing"))
                continue
            }

            let diskSize = (attrs[.size] as? Int) ?? -1
            let diskInode = (attrs[.systemFileNumber] as? UInt64) ?? 0
            let diskMTime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            if let record = cas.verifyRecord(for: member.sha256),
               record.size == diskSize, record.inode == diskInode, record.mtime == diskMTime {
                continue // cheap check passes — no re-hash, no network
            }

            // Cheap check disagreed (or no verify record exists yet) —
            // fall back to a full local re-hash, still zero network.
            guard let rehashed = try? rehash(objectURL) else {
                blockers.append(ReadinessBlocker(sha256: member.sha256, reason: "unreadable"))
                continue
            }
            if rehashed != member.sha256 {
                blockers.append(ReadinessBlocker(sha256: member.sha256, reason: "corrupted"))
            }
        }

        return blockers.isEmpty ? .ready : .blocked(blockers)
    }

    private func rehash(_ url: URL) throws -> String {
        var hasher = try StreamingSHA256.resume(from: url)
        return hasher.finalizeHex()
    }
}
