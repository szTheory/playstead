import Foundation

/// Gates launch on six real, entirely local checks — game assets, local
/// cache verification, emulator, BIOS, controller/input, and the
/// persistent-save path — returning an ordered report where every
/// blocking result carries an executable `Remedy`. This is the only gate
/// between a user pressing Play and the adapter host launching; a check
/// that is not here is a check that does not happen.
///
/// **Zero network calls, ever.** Not a reachability probe, not a
/// metadata lookup, not a token refresh — the promise is that a
/// verified local game launches on a plane, and any network call on this
/// path is a way for that promise to fail. Every dependency below is
/// either a pure closure or a type (`CASManager`, `DownloadQueue`,
/// `FileManager`) whose calls in this file are entirely local disk/SQLite
/// operations.
///
/// **Pure with respect to disk**, with exactly one documented exception:
/// a genuine cache-object corruption quarantines the bad bytes and
/// enqueues a redownload. Every other check only reads — running
/// `evaluate` twice on unchanged inputs produces an identical report and
/// changes nothing else on disk.
struct ReadinessEngine {
    let cas: CASManager
    let downloadQueue: DownloadQueue
    /// Resolved from `AdapterInstaller`/`AdapterHost`'s current state.
    let adapterInstallState: () -> AdapterInstallState
    /// From `AdapterDescriptor.biosRequired` — whether a BIOS is a hard
    /// launch requirement for this adapter, or an optional fidelity
    /// upgrade over its built-in implementation.
    let biosRequired: Bool
    /// From `BiosStore.hasManagedBIOS(forSystem:)`.
    let hasManagedBIOS: () -> Bool
    let hasController: () -> Bool
    /// A Mac always effectively has a keyboard available; injectable for
    /// tests only.
    let hasKeyboard: () -> Bool
    let saveDirectoryURL: URL
    let now: () -> Date

    init(
        cas: CASManager,
        downloadQueue: DownloadQueue,
        adapterInstallState: @escaping () -> AdapterInstallState,
        biosRequired: Bool,
        hasManagedBIOS: @escaping () -> Bool,
        hasController: @escaping () -> Bool = { false },
        hasKeyboard: @escaping () -> Bool = { true },
        saveDirectoryURL: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.cas = cas
        self.downloadQueue = downloadQueue
        self.adapterInstallState = adapterInstallState
        self.biosRequired = biosRequired
        self.hasManagedBIOS = hasManagedBIOS
        self.hasController = hasController
        self.hasKeyboard = hasKeyboard
        self.saveDirectoryURL = saveDirectoryURL
        self.now = now
    }

    /// The fixed declaration order every evaluation starts from — also
    /// this ordering's tie-break when two checks share the same
    /// severity, which is what keeps repeated evaluations on unchanged
    /// inputs producing an identical report.
    private static let kindOrder: [ReadinessCheckKind] = [
        .gameAssets, .cacheVerification, .emulator, .bios, .controllerAndInput, .saveDirectory
    ]

    func evaluate(assetSetID: String, requiredMembers: [RequiredMember]) -> ReadinessReport {
        let (assetsCheck, cacheCheck) = evaluateAssetsAndCache(assetSetID: assetSetID, requiredMembers: requiredMembers)
        let checks = [
            assetsCheck,
            cacheCheck,
            evaluateEmulator(),
            evaluateBIOS(),
            evaluateControllerAndInput(),
            evaluateSaveDirectory()
        ]
        return ReadinessReport(checks: order(checks))
    }

    // MARK: - Game assets + local cache verification

    private func evaluateAssetsAndCache(
        assetSetID: String, requiredMembers: [RequiredMember]
    ) -> (ReadinessCheck, ReadinessCheck) {
        guard !requiredMembers.isEmpty else {
            return (
                ReadinessCheck(kind: .gameAssets, outcome: .ready, finding: "This title has no required files.", remedy: nil),
                ReadinessCheck(kind: .cacheVerification, outcome: .ready, finding: "Nothing to verify.", remedy: nil)
            )
        }

        let preflight = PreflightChecker(cas: cas)
        let tupleMembers = requiredMembers.map { (sha256: $0.sha256, size: $0.size) }
        let result = preflight.check(requiredMembers: tupleMembers)

        guard case .blocked(let blockers) = result else {
            return (
                ReadinessCheck(kind: .gameAssets, outcome: .ready, finding: "All required files are present.", remedy: nil),
                ReadinessCheck(kind: .cacheVerification, outcome: .ready, finding: "All required files verified intact.", remedy: nil)
            )
        }

        let missing = blockers.filter { $0.reason == "missing" }
        let unverifiable = blockers.filter { $0.reason != "missing" }

        // A genuine local-copy failure (corrupted or unreadable): the
        // bytes are still safe on the server, so quarantine what's here
        // and enqueue a redownload — the one documented disk write this
        // engine ever performs.
        for blocker in unverifiable {
            quarantineAndRequeue(assetSetID: assetSetID, sha256: blocker.sha256, requiredMembers: requiredMembers)
        }

        let assetsCheck: ReadinessCheck
        if missing.isEmpty {
            assetsCheck = ReadinessCheck(kind: .gameAssets, outcome: .ready, finding: "All required files are present.", remedy: nil)
        } else {
            let names = missing.map(\.sha256).joined(separator: ", ")
            assetsCheck = ReadinessCheck(
                kind: .gameAssets,
                outcome: .blocked("Missing \(missing.count) required file(s): \(names)"),
                finding: "This title is missing \(missing.count) required file(s) that haven't been downloaded yet.",
                remedy: Remedy(title: "Download missing files", action: .downloadMember(sha256: missing[0].sha256))
            )
        }

        let cacheCheck: ReadinessCheck
        if unverifiable.isEmpty {
            cacheCheck = ReadinessCheck(kind: .cacheVerification, outcome: .ready, finding: "All required files verified intact.", remedy: nil)
        } else {
            let names = unverifiable.map(\.sha256).joined(separator: ", ")
            cacheCheck = ReadinessCheck(
                kind: .cacheVerification,
                outcome: .blocked("Local copy replaced: \(names)"),
                finding: "A local copy didn't match what was expected. This wasn't caused by anything you did — it's being replaced automatically.",
                remedy: Remedy(title: "Redownload the affected file", action: .downloadMember(sha256: unverifiable[0].sha256))
            )
        }

        return (assetsCheck, cacheCheck)
    }

    /// Quarantines a corrupted/unreadable committed cache object by
    /// moving its bytes aside (never deleting outright — evidence for
    /// diagnosing a bad transfer stays on disk, exactly as
    /// `CASManager.quarantine(partialAt:reason:)` does for a failed
    /// partial), clears its stale verify-index entry, and enqueues a
    /// fresh download for the same member.
    private func quarantineAndRequeue(assetSetID: String, sha256: String, requiredMembers: [RequiredMember]) {
        let fm = FileManager.default
        // A malformed digest has no object to quarantine and must not be
        // spliced into the quarantine destination below (CR-02).
        guard let objectURL = try? cas.objectURL(for: sha256) else { return }
        if fm.fileExists(atPath: objectURL.path) {
            let quarantineDir = cas.paths.partials.appendingPathComponent("quarantine", isDirectory: true)
            try? fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            let stamp = Int(now().timeIntervalSince1970 * 1000)
            let dest = quarantineDir.appendingPathComponent("\(sha256).\(stamp)")
            try? fm.moveItem(at: objectURL, to: dest)
        }
        try? cas.remove(sha256)

        guard let member = requiredMembers.first(where: { $0.sha256 == sha256 }) else { return }
        let entry = CatalogueEntry(
            id: assetSetID, system: "", displayTitle: "",
            tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: sha256, size: member.size, name: nil)]
        )
        try? downloadQueue.enqueueGame(entry)
    }

    // MARK: - Emulator

    private func evaluateEmulator() -> ReadinessCheck {
        switch adapterInstallState() {
        case .notInstalled:
            return ReadinessCheck(
                kind: .emulator,
                outcome: .blocked("Adapter not installed."),
                finding: "The adapter hasn't been installed yet.",
                remedy: Remedy(title: "Install adapter", action: .installAdapter)
            )
        case .installed(let path, let verified):
            guard FileManager.default.fileExists(atPath: path) else {
                return ReadinessCheck(
                    kind: .emulator,
                    outcome: .blocked("Adapter files missing."),
                    finding: "The installed adapter could not be found on disk.",
                    remedy: Remedy(title: "Install adapter", action: .installAdapter)
                )
            }
            guard verified else {
                return ReadinessCheck(
                    kind: .emulator,
                    outcome: .blocked("Adapter installation unverified."),
                    finding: "This installation's digest does not match the pinned release.",
                    remedy: Remedy(title: "Install adapter", action: .installAdapter)
                )
            }
            return ReadinessCheck(kind: .emulator, outcome: .ready, finding: "Adapter installed and verified.", remedy: nil)
        }
    }

    // MARK: - BIOS

    private func evaluateBIOS() -> ReadinessCheck {
        if hasManagedBIOS() {
            return ReadinessCheck(kind: .bios, outcome: .ready, finding: "BIOS validated.", remedy: nil)
        }
        if biosRequired {
            return ReadinessCheck(
                kind: .bios,
                outcome: .blocked("BIOS required."),
                finding: "This adapter requires a BIOS file that hasn't been validated yet.",
                remedy: Remedy(title: "Drop in a BIOS file", action: .openBiosDropTarget)
            )
        }
        return ReadinessCheck(
            kind: .bios,
            outcome: .ready,
            finding: "No BIOS present — the adapter's built-in implementation is used instead.",
            remedy: nil
        )
    }

    // MARK: - Controller and input

    private func evaluateControllerAndInput() -> ReadinessCheck {
        if hasController() {
            return ReadinessCheck(kind: .controllerAndInput, outcome: .ready, finding: "Controller connected.", remedy: nil)
        }
        if hasKeyboard() {
            return ReadinessCheck(kind: .controllerAndInput, outcome: .ready, finding: "Keyboard available.", remedy: nil)
        }
        return ReadinessCheck(
            kind: .controllerAndInput,
            outcome: .blocked("No input device available."),
            finding: "No controller or keyboard is currently available.",
            remedy: Remedy(title: "Open input settings", action: .openInputSettings)
        )
    }

    // MARK: - Save directory

    private func evaluateSaveDirectory() -> ReadinessCheck {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: saveDirectoryURL.path, isDirectory: &isDir)
        let writable = exists && isDir.boolValue && fm.isWritableFile(atPath: saveDirectoryURL.path)
        guard writable else {
            return ReadinessCheck(
                kind: .saveDirectory,
                outcome: .blocked("Save directory not writable."),
                finding: "Playstead can't currently write saves to its save directory.",
                remedy: Remedy(title: "Repair save directory", action: .repairSaveDirectory)
            )
        }
        return ReadinessCheck(kind: .saveDirectory, outcome: .ready, finding: "Save directory is writable.", remedy: nil)
    }

    // MARK: - Ordering

    /// Orders by severity (blocked, then warning, then ready) and, within
    /// the same severity, by this type's own fixed declaration order —
    /// a stable sort over two deterministic keys, so the same inputs
    /// always produce the same order.
    private func order(_ checks: [ReadinessCheck]) -> [ReadinessCheck] {
        func rank(_ outcome: ReadinessOutcome) -> Int {
            switch outcome {
            case .blocked: return 0
            case .warning: return 1
            case .ready: return 2
            }
        }
        return checks.sorted { lhs, rhs in
            let lhsRank = rank(lhs.outcome)
            let rhsRank = rank(rhs.outcome)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let lhsIndex = Self.kindOrder.firstIndex(of: lhs.kind) ?? 0
            let rhsIndex = Self.kindOrder.firstIndex(of: rhs.kind) ?? 0
            return lhsIndex < rhsIndex
        }
    }
}
