import Foundation

/// Reports this device's own per-asset-set availability facts to
/// `PUT /api/v1/devices/me/availability` (plan 03-14, LIBR-02 gap
/// closure) — an after-the-fact outbox producer copied from
/// `PlaySessionRecorder`'s posture exactly (see that type's doc
/// comment): never called from a launch path, never surfaces a
/// transport failure to the user, and structurally incapable of making
/// a launch depend on it, because nothing on the launch path holds a
/// reference to this type at all.
///
/// Every report is a full replacement of this device's current fact
/// set, matching the server's `Playstead.Availability.replace_for_
/// device/2` semantics exactly — the complete current set for this
/// device, not an incremental delta. Sends FACTS, never a derived
/// state name: `AvailabilityState`'s six-case ladder rank is the
/// server's alone to compute (D-21). A report entry carries
/// `downloading`/`verified`/`pinned`/`download_percent`, never a
/// `state` or `rank` field, and this type never calls
/// `AvailabilityState.derive(_:)` itself.
///
/// Reads the same facts `AvailabilityState.derive(_:)`'s callers read,
/// from the same stores: `DownloadQueue` (for an active, non-cancelled
/// transfer of a required member) and `CASManager` (for whether every
/// required member is committed) and `PinStore` (for the pin flag).
/// `AvailabilityState.swift` itself is never modified or imported by
/// this file beyond what Swift's whole-module visibility already gives
/// every file in this target.
final class AvailabilityReporter {
    private let localStore: LocalStore
    private let downloadQueue: DownloadQueue
    private let cas: CASManager
    private let pinStore: PinStore
    private let outbox: Outbox
    private let idGenerator: () -> String
    /// The live transfer percent for an asset set currently `.active` in
    /// `DownloadQueue`, if known — wired at the composition root to
    /// `DownloadCoordinator.progressPercent(forAssetSet:)` (the same
    /// accessor `AvailabilityInputs` callers use), an `actor` method
    /// this reporter would otherwise have to depend on directly. Kept as
    /// an injected closure, matching `DownloadCoordinator`'s own
    /// `isPinned`/`quotaCheck` seam pattern, so a test can drive this
    /// with an injected value instead of constructing a real
    /// `DownloadCoordinator` (which itself needs a live `DownloadEngine`
    /// and `Reachability`). Defaults to "unknown" — a valid `0` is sent
    /// rather than a fabricated live number.
    ///
    /// A `var`, set post-construction via
    /// `setActiveTransferPercentProvider(_:)`, exactly like
    /// `DownloadCoordinator.isPinned`/`quotaCheck`'s own seam — not an
    /// `init` parameter, because the composition root's real provider
    /// closure captures `self` (`AppEnvironment`) weakly, and a stored
    /// property whose own initial value is a self-capturing closure
    /// cannot be assigned inside `init` before every other stored
    /// property (including this reporter itself) is already set.
    private var activeTransferPercent: (String) async -> Int?

    init(
        localStore: LocalStore,
        downloadQueue: DownloadQueue,
        cas: CASManager,
        pinStore: PinStore,
        outbox: Outbox,
        activeTransferPercent: @escaping (String) async -> Int? = { _ in nil },
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.localStore = localStore
        self.downloadQueue = downloadQueue
        self.cas = cas
        self.pinStore = pinStore
        self.outbox = outbox
        self.activeTransferPercent = activeTransferPercent
        self.idGenerator = idGenerator
    }

    /// Wires the live-percent seam to a real
    /// `DownloadCoordinator.progressPercent(forAssetSet:)` (or any test
    /// double) after construction — the `DownloadCoordinator.setIsPinned`/
    /// `setQuotaCheck` pattern, reused here for the same reason: the real
    /// provider closure needs to capture `self` (`AppEnvironment`) weakly,
    /// which cannot happen inside that type's own `init`.
    func setActiveTransferPercentProvider(_ provider: @escaping (String) async -> Int?) {
        activeTransferPercent = provider
    }

    /// Builds one entry per catalogue game this client currently knows
    /// about — a game with no local bytes and no active queue row still
    /// gets an entry with every fact `false`, never omitted — and
    /// enqueues the complete set through `Outbox` as one
    /// full-replacement `.availabilityReport` intent, exactly as
    /// `PlaySessionRecorder.ended(_:at:)` enqueues its own intent.
    ///
    /// Never throws and never surfaces failure to its caller:
    /// `Outbox.enqueue`'s own failure (a durable-write error) is
    /// swallowed with `try?`, matching `PlaySessionRecorder`'s
    /// discipline exactly, since a report failure must never become a
    /// reason to interrupt whatever background pass (`syncNow()`)
    /// called this. With the server unreachable, the enqueued entry is
    /// simply drained later by `OutboxWorker`, on its own retry
    /// schedule — no error surfaces here and nothing about a launch is
    /// affected either way.
    @discardableResult
    func reportAll() async -> [AvailabilityReportEntry] {
        let entries = await buildEntries(catalogue: localStore.fetchCatalogue())
        _ = try? outbox.enqueue(.availabilityReport(id: idGenerator(), entries: entries))
        return entries
    }

    /// The pure entry-building step, exposed separately so a test can
    /// assert the exact facts computed for a given catalogue/store
    /// state without also touching the outbox.
    func buildEntries(catalogue: [CatalogueEntry]) async -> [AvailabilityReportEntry] {
        let pinnedAssetSetIDs = pinStore.allPinned()
        var entries: [AvailabilityReportEntry] = []
        entries.reserveCapacity(catalogue.count)

        for game in catalogue {
            let requiredSHAs = game.members.filter(\.required).compactMap(\.sha256)
            let allRequiredCached = !requiredSHAs.isEmpty
                && requiredSHAs.allSatisfy { self.cas.contains($0) }

            // A required member currently `.active` (never `.waiting`,
            // `.paused`, or `.cancelled`) is this game's one live
            // transfer — `DownloadCoordinator` drives exactly one at a
            // time, so at most one such item can exist per asset set.
            let isDownloading = downloadQueue.itemsForAssetSet(game.id)
                .contains { $0.state == .active && requiredSHAs.contains($0.sha256) }

            // A valid in-range `0` when the live percent is unknown
            // (e.g. no `DownloadCoordinator` transfer is actually
            // running for this asset set despite a stale `.active` row,
            // or none was injected) — never a fabricated number.
            let percent = isDownloading ? (await activeTransferPercent(game.id) ?? 0) : 0

            entries.append(AvailabilityReportEntry(
                assetSetID: game.id,
                downloading: isDownloading,
                verified: allRequiredCached,
                pinned: pinnedAssetSetIDs.contains(game.id),
                missingDependency: false,
                downloadPercent: percent
            ))
        }
        return entries
    }
}
