#if UI_TESTING
import CryptoKit
import Foundation

enum DeterministicProfileError: Error, Equatable {
    case missingProfile
    case unknownProfile(String)
    case stateMismatch(String)
}

/// The only local states a UI-testing build may request.
///
/// Raw values are control-plane vocabulary, never SQL, paths, filenames,
/// credentials, or user data. Each case maps to fixed synthetic state below.
enum DeterministicProfile: String, CaseIterable {
    case emptyLibrary = "empty-library"
    case populatedCurationReorder = "populated-curation-reorder"
    case pausedActiveQueue = "paused-active-queue"
    case quotaBlockReclaim = "quota-block-reclaim"
    case storage = "storage"
    /// 04-18 Journey 1 (SAVE-03): one game, its ROM cached, an empty
    /// local save directory, and one `uploaded` restorable revision
    /// committed for its content key -- a normal launch through the
    /// real Play button should restore it. No routing flag ever
    /// presents anything; this only seeds the world Play walks into.
    case saveRestorable = "save-restorable"
    /// 04-18 Journey 2 (D-40): one cached, evictable game whose only
    /// committed save revision is `localOnly` -- reclaiming it through
    /// the real Storage surface must raise the D-40 interruptive modal.
    case saveOnlyCopy = "save-only-copy"
    /// 04-18 Journeys 3 and 4 (D-38/D-37): one cached game with two
    /// undisposed heads on the same save line -- a genuine fork the
    /// card's badge and the readiness Save row must both report.
    case saveDiverged = "save-diverged"

    /// A real, offline, synthetic pairing credential this profile's
    /// world requires -- `nil` for every profile that has no reason to
    /// be paired. `.saveOnlyCopy` needs one so MC-02's "Export saves…"
    /// escape hatch resolves a real URL through `AppEnvironment
    /// .openConsoleSavesExport` (never a routing flag: whether this Mac
    /// is paired is ordinary background state, not navigation to the
    /// surface under test). This performs no network I/O -- resolving
    /// the URL is pure, and the actual `NSWorkspace.shared.open` call it
    /// would otherwise make is unconditionally skipped under
    /// `UI_TESTING`.
    var uiTestingCredential: PairingCredential? {
        switch self {
        case .saveOnlyCopy:
            return PairingCredential(
                deviceID: "ui-test-device",
                baseURL: URL(string: "https://ui-test.invalid")!,
                token: "ui-test-token"
            )
        default:
            return nil
        }
    }

    static func parse(_ value: String?) throws -> DeterministicProfile {
        guard let value, !value.isEmpty else { throw DeterministicProfileError.missingProfile }
        guard let profile = Self(rawValue: value) else {
            throw DeterministicProfileError.unknownProfile(value)
        }
        return profile
    }

    func makeFixture(
        sessionID: String? = nil,
        fileManager: FileManager = .default
    ) throws -> DeterministicProfileFixture {
        let persistentRoot = try sessionID.map { try Self.persistentRoot(sessionID: $0, fileManager: fileManager) }
        let root = persistentRoot ?? fileManager.temporaryDirectory
            .appendingPathComponent("playstead-ui-profile-\(UUID().uuidString)", isDirectory: true)
        let databaseExisted = fileManager.fileExists(atPath: root.appendingPathComponent("playstead.sqlite3").path)
        let paths = AppPaths(root: root, fileManager: fileManager)

        do {
            let localStore = try LocalStore(paths: paths)
            let fixture = DeterministicProfileFixture(
                profile: self,
                root: root,
                paths: paths,
                localStore: localStore,
                catalogueStore: CatalogueStore(localStore: localStore),
                curationStore: CurationStore(localStore: localStore),
                downloadQueue: DownloadQueue(
                    localStore: localStore,
                    idGenerator: DeterministicProfileFixture.nextQueueID,
                    now: { DeterministicProfileFixture.timestamp }
                ),
                pinStore: PinStore(localStore: localStore, now: { DeterministicProfileFixture.timestamp }),
                quotaManager: QuotaManager(
                    localStore: localStore,
                    cacheRootURL: paths.objects,
                    freeSpaceProvider: { Int.max }
                ),
                saveStore: SaveStore(localStore: localStore),
                preservesRootForRelaunch: persistentRoot != nil
            )
            if databaseExisted {
                try fixture.assertPersistentSessionState()
            } else {
                try fixture.seed()
                try fixture.assertExactState()
            }
            return fixture
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    /// A test may supply only one UUID token, never a path. The token is
    /// resolved beneath a fixed temporary parent so relaunch exercises the
    /// same on-disk SQLite store without opening an arbitrary-file surface.
    private static func persistentRoot(sessionID: String, fileManager: FileManager) throws -> URL {
        guard
            let uuid = UUID(uuidString: sessionID),
            uuid.uuidString.lowercased() == sessionID.lowercased()
        else {
            throw DeterministicProfileError.stateMismatch("invalid UI-test session id")
        }
        return fileManager.temporaryDirectory
            .appendingPathComponent("playstead-ui-profile-sessions", isDirectory: true)
            .appendingPathComponent(uuid.uuidString.lowercased(), isDirectory: true)
    }
}

struct DeterministicProfileExpectation: Equatable {
    let catalogueCount: Int
    let favoriteCount: Int
    let collectionCount: Int
    let collectionMemberCount: Int
    let collectionPositions: [String]
    let queueCount: Int
    let queueStates: Set<QueueItemState>
    let pinnedAssetSetIDs: Set<String>
    let cachedObjectCount: Int
    let quotaPolicy: QuotaPolicy
}

final class DeterministicProfileFixture {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
    private static var queueSequence = 0

    let profile: DeterministicProfile
    let root: URL
    let paths: AppPaths
    let localStore: LocalStore
    let catalogueStore: CatalogueStore
    let curationStore: CurationStore
    let downloadQueue: DownloadQueue
    let pinStore: PinStore
    let quotaManager: QuotaManager
    let saveStore: SaveStore
    let preservesRootForRelaunch: Bool

    var expected: DeterministicProfileExpectation {
        switch profile {
        case .emptyLibrary:
            return expectation(catalogue: 0)
        case .populatedCurationReorder:
            return expectation(
                catalogue: 3,
                favorites: 1,
                collections: 1,
                members: 3,
                positions: ["6", "i", "u"]
            )
        case .pausedActiveQueue:
            return expectation(
                catalogue: 3,
                queue: 3,
                queueStates: [.active, .paused, .waiting]
            )
        case .quotaBlockReclaim:
            return expectation(
                catalogue: 2,
                cached: 1,
                quota: QuotaPolicy(quotaBytes: 16, floorBytes: QuotaPolicy.defaultPolicy.floorBytes)
            )
        case .storage:
            return expectation(
                catalogue: 1,
                pinned: [Self.storageAssetID],
                cached: 1
            )
        case .saveRestorable:
            return expectation(catalogue: 1, cached: 1)
        case .saveOnlyCopy:
            return expectation(catalogue: 1, cached: 1)
        case .saveDiverged:
            return expectation(catalogue: 1, cached: 1)
        }
    }

    fileprivate init(
        profile: DeterministicProfile,
        root: URL,
        paths: AppPaths,
        localStore: LocalStore,
        catalogueStore: CatalogueStore,
        curationStore: CurationStore,
        downloadQueue: DownloadQueue,
        pinStore: PinStore,
        quotaManager: QuotaManager,
        saveStore: SaveStore,
        preservesRootForRelaunch: Bool
    ) {
        self.profile = profile
        self.root = root
        self.paths = paths
        self.localStore = localStore
        self.catalogueStore = catalogueStore
        self.curationStore = curationStore
        self.downloadQueue = downloadQueue
        self.pinStore = pinStore
        self.quotaManager = quotaManager
        self.saveStore = saveStore
        self.preservesRootForRelaunch = preservesRootForRelaunch
    }

    func cleanup(fileManager: FileManager = .default) throws {
        guard root.lastPathComponent.hasPrefix("playstead-ui-profile-") else {
            throw DeterministicProfileError.stateMismatch("refused cleanup outside generated profile root")
        }
        localStore.connection.close()
        try fileManager.removeItem(at: root)
    }

    func assertExactState() throws {
        let actual = DeterministicProfileExpectation(
            catalogueCount: catalogueStore.count(),
            favoriteCount: curationStore.fetchFavorites().count,
            collectionCount: curationStore.fetchCollections().count,
            collectionMemberCount: curationStore.fetchCollectionMembers().count,
            collectionPositions: curationStore.fetchCollectionMembers().map(\.position),
            queueCount: downloadQueue.list().count,
            queueStates: Set(downloadQueue.list().map(\.state)),
            pinnedAssetSetIDs: pinStore.allPinned(),
            cachedObjectCount: scalarCount("SELECT COUNT(*) FROM cache_objects;"),
            quotaPolicy: quotaManager.policy()
        )
        guard actual == expected else {
            throw DeterministicProfileError.stateMismatch("\(profile.rawValue): expected \(expected), got \(actual)")
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.databaseURL.path),
              [paths.objects, paths.partials, paths.launch, paths.emulators, paths.bios]
                .allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw DeterministicProfileError.stateMismatch("\(profile.rawValue): isolated path layout is incomplete")
        }

        if profile == .quotaBlockReclaim {
            let target = catalogueStore.fetchAll().first { $0.id == Self.quotaDownloadAssetID }
            let pendingBytes = target?.members.filter(\.required).compactMap(\.size).reduce(0, +)
            let verdict = pendingBytes.map { quotaManager.verdict(forAdditional: $0) }
            guard quotaManager.usedBytes() == 32,
                  quotaManager.policy().quotaBytes == 16,
                  pendingBytes == 32,
                  verdict == QuotaVerdict(allowed: false, limitHit: .quota, shortfallBytes: 48),
                  EvictionPlanner(
                    localStore: localStore,
                    catalogueStore: catalogueStore,
                    pinStore: pinStore,
                    cas: CASManager(paths: paths),
                    paths: paths
                  ).candidates().map(\.id) == [Self.quotaAssetID] else {
                throw DeterministicProfileError.stateMismatch("quota profile did not compute used=32,pending=32,quota=16,shortfall=48 with one reclaim candidate")
            }
        }
    }

    /// A persisted profile intentionally differs from its seed after a
    /// reorder. Reopen validation therefore pins the invariant inventory
    /// and content identities while allowing only order/outbox state to
    /// carry across the process boundary.
    func assertPersistentSessionState() throws {
        guard profile == .populatedCurationReorder else {
            throw DeterministicProfileError.stateMismatch("only the curation profile supports relaunch")
        }
        let members = curationStore.fetchCollectionMembers()
        let digests = catalogueStore.fetchAll().flatMap(\.members).compactMap(\.sha256).sorted()
        let expectedDigests = Self.catalogueEntries(count: 3).flatMap(\.members).compactMap(\.sha256).sorted()
        guard catalogueStore.count() == 3,
              curationStore.fetchFavorites().count == 1,
              curationStore.fetchCollections().count == 1,
              members.count == 3,
              Set(members.map(\.id)).count == 3,
              digests == expectedDigests else {
            throw DeterministicProfileError.stateMismatch("persisted curation fixture inventory drifted")
        }
    }

    fileprivate func seed() throws {
        switch profile {
        case .emptyLibrary:
            break
        case .populatedCurationReorder:
            let entries = Self.catalogueEntries(count: 3)
            try catalogueStore.replaceAll(entries)
            try curationStore.upsertFavorite(
                id: "00000000-0000-7000-8000-000000000101",
                assetSetID: entries[0].id,
                createdAt: Self.timestampString
            )
            try curationStore.upsertCollection(
                id: Self.collectionID,
                name: "Synthetic Collection",
                createdAt: Self.timestampString,
                updatedAt: Self.timestampString
            )
            for (index, position) in ["6", "i", "u"].enumerated() {
                try curationStore.upsertCollectionMember(
                    id: "00000000-0000-7000-8000-00000000020\(index + 1)",
                    collectionID: Self.collectionID,
                    assetSetID: entries[index].id,
                    position: position,
                    addedAt: Self.timestampString
                )
            }
        case .pausedActiveQueue:
            let entries = Self.catalogueEntries(count: 3)
            try catalogueStore.replaceAll(entries)
            for entry in entries { try downloadQueue.enqueueGame(entry) }
            let rows = downloadQueue.list()
            try downloadQueue.markActive(id: rows[0].id)
            try downloadQueue.pause(id: rows[1].id)
        case .quotaBlockReclaim:
            let entry = Self.entry(id: Self.quotaAssetID, title: "Synthetic Reclaim Candidate", seed: 41)
            try catalogueStore.upsert(entry)
            try seedCachedObject(for: entry, bytes: 32, seed: 41)
            try catalogueStore.upsert(Self.entry(
                id: Self.quotaDownloadAssetID,
                title: "Synthetic Quota Download",
                seed: 42
            ))
            try quotaManager.setQuota(bytes: 16)
        case .storage:
            let entry = Self.entry(id: Self.storageAssetID, title: "Synthetic Offline Fixture", seed: 73)
            try catalogueStore.upsert(entry)
            try seedCachedObject(for: entry, bytes: 32, seed: 73)
            try pinStore.pin(assetSetID: entry.id)
        case .saveRestorable:
            // Journey 1 (SAVE-03): the ROM is cached (so readiness's
            // asset/cache checks are `.ready`) and the save directory
            // starts empty (never created here) -- the only thing that
            // exists ahead of a normal launch is one `uploaded`,
            // restorable revision on the content key Play itself
            // resolves. A real, installed adapter is also seeded so the
            // front door -- pressing Play -- reaches
            // `LaunchSavePlanner`/`SavePlanExecutor` rather than
            // stopping at the "adapter not installed" readiness check
            // first, which would prove nothing about SAVE-03.
            let entry = Self.entry(id: Self.saveRestorableAssetID, title: "Synthetic Save Restore", seed: 91)
            try catalogueStore.upsert(entry)
            try seedCachedObject(for: entry, bytes: 32, seed: 91)
            let contentKey = try requiredDigest(of: entry)
            let saveBytes = Data(repeating: 0x5A, count: Self.saveArtifactBytes)
            let saveDigest = Self.digest(of: saveBytes)
            try commitBlob(saveBytes, digest: saveDigest)
            let line = try saveStore.resolveLine(
                contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-restorable"
            )
            try saveStore.insertRevision(SaveRevisionRow(
                id: "rev-restorable-1",
                saveLineID: line.id,
                parentRevisionID: nil,
                blobSHA256: saveDigest,
                sizeBytes: saveBytes.count,
                originDeviceID: "another-mac",
                deviceCapturedAt: nil,
                recordedAt: Self.timestampString,
                captureMethod: "poller",
                adapterID: nil,
                adapterVersion: nil,
                saveFormat: nil,
                formatConfidence: nil,
                playSessionID: nil,
                durability: SaveDurability.uploaded.rawValue,
                localPath: nil
            ))
            try installFakeAdapter()
        case .saveOnlyCopy:
            // Journey 2 (D-40): a cached, evictable game whose one
            // committed revision is `localOnly` -- reclaiming it through
            // the real Storage surface must raise the interruptive modal.
            let entry = Self.entry(id: Self.saveOnlyCopyAssetID, title: "Synthetic Only Copy Game", seed: 92)
            try catalogueStore.upsert(entry)
            try seedCachedObject(for: entry, bytes: 32, seed: 92)
            let contentKey = try requiredDigest(of: entry)
            let saveBytes = Data(repeating: 0x5B, count: Self.saveArtifactBytes)
            let saveDigest = Self.digest(of: saveBytes)
            try commitBlob(saveBytes, digest: saveDigest)
            let line = try saveStore.resolveLine(
                contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-only-copy"
            )
            try saveStore.insertRevision(SaveRevisionRow(
                id: "rev-only-copy-1",
                saveLineID: line.id,
                parentRevisionID: nil,
                blobSHA256: saveDigest,
                sizeBytes: saveBytes.count,
                originDeviceID: "this-mac",
                deviceCapturedAt: nil,
                recordedAt: Self.timestampString,
                captureMethod: "poller",
                adapterID: nil,
                adapterVersion: nil,
                saveFormat: nil,
                formatConfidence: nil,
                playSessionID: nil,
                durability: SaveDurability.localOnly.rawValue,
                localPath: nil
            ))
        case .saveDiverged:
            // Journeys 3 and 4 (D-38/D-37): two undisposed heads on the
            // same line -- a genuine, unacknowledged fork. Neither head
            // is a parent of the other, so both remain current heads.
            let entry = Self.entry(id: Self.saveDivergedAssetID, title: "Synthetic Diverged Game", seed: 93)
            try catalogueStore.upsert(entry)
            try seedCachedObject(for: entry, bytes: 32, seed: 93)
            let contentKey = try requiredDigest(of: entry)
            let line = try saveStore.resolveLine(
                contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-diverged"
            )
            for (suffix, seed, origin) in [("a", UInt8(0x5C), "this-mac"), ("b", UInt8(0x5D), "another-mac")] {
                let bytes = Data(repeating: seed, count: Self.saveArtifactBytes)
                let digest = Self.digest(of: bytes)
                try commitBlob(bytes, digest: digest)
                try saveStore.insertRevision(SaveRevisionRow(
                    id: "rev-diverged-\(suffix)",
                    saveLineID: line.id,
                    parentRevisionID: nil,
                    blobSHA256: digest,
                    sizeBytes: bytes.count,
                    originDeviceID: origin,
                    deviceCapturedAt: nil,
                    recordedAt: Self.timestampString,
                    captureMethod: "poller",
                    adapterID: nil,
                    adapterVersion: nil,
                    saveFormat: nil,
                    formatConfidence: nil,
                    playSessionID: nil,
                    durability: SaveDurability.localOnly.rawValue,
                    localPath: nil
                ))
            }
        }
    }

    /// The ROM's own sha256 -- the content key a save line is keyed by
    /// (D-10), exactly matching `AppEnvironment.saveContentKey(for:)`.
    private func requiredDigest(of entry: CatalogueEntry) throws -> String {
        guard let digest = entry.members.first?.sha256 else {
            throw DeterministicProfileError.stateMismatch("fixture entry is missing its digest")
        }
        return digest
    }

    /// D-50/the pinned adapter's `sram_32k` medium: the one proven save
    /// size (`AdapterPin.json`'s `save_contract.proven_media`), so a
    /// seeded revision satisfies `SaveCompatibilityGate` exactly like a
    /// real GBA battery save would, rather than tripping the D-24
    /// unbound-medium hard block with an arbitrary byte count.
    private static let saveArtifactBytes = 32_768

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Commits arbitrary bytes into CAS under their own digest, with no
    /// `cache_objects` row -- unlike `seedCachedObject`, a save blob is
    /// tracked by `save_revision.blob_sha256`, never the game-asset cache
    /// index. `CASManager.contains(_:)` only ever checks the object file
    /// itself.
    private func commitBlob(_ data: Data, digest: String) throws {
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial, options: .atomic)
        try CASManager(paths: paths).commit(partialAt: partial, sha256: digest)
    }

    /// Seeds a real, on-disk "installed adapter" so `ReadinessEngine`'s
    /// emulator check reads `.ready` and `AdapterHost.launch` has a real
    /// executable to spawn -- exactly the same on-disk shape
    /// `AdapterInstaller.recordInstallation`/`selectExisting` produce
    /// for a user-selected build, seeded directly rather than through a
    /// real download because these fixtures run with no network. The
    /// script's own bytes are what get hashed and recorded, so the
    /// installation's digest baseline is trivially self-consistent.
    private func installFakeAdapter() throws {
        let pin = try AdapterPin.load()
        let scriptURL = paths.emulators.appendingPathComponent(
            "ui-test-fake-adapter", isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: paths.emulators, withIntermediateDirectories: true
        )
        let scriptBytes = Data("#!/bin/sh\nexit 0\n".utf8)
        try scriptBytes.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path
        )
        let executableDigest = Self.digest(of: scriptBytes)
        try localStore.connection.execute(
            """
            INSERT INTO adapter_installations
                (id, emulator, version, executable_path, sha256, archive_sha256, provenance, verified, installed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(emulator, version) DO UPDATE SET
                executable_path = excluded.executable_path,
                sha256 = excluded.sha256,
                archive_sha256 = excluded.archive_sha256,
                provenance = excluded.provenance,
                verified = excluded.verified,
                installed_at = excluded.installed_at;
            """,
            params: [
                UUID().uuidString, pin.emulator, pin.version, scriptURL.path,
                executableDigest, nil as String?, "userSelected", 1, Self.timestampString
            ]
        )
    }

    private func seedCachedObject(for entry: CatalogueEntry, bytes: Int, seed: UInt8) throws {
        guard let digest = entry.members.first?.sha256 else {
            throw DeterministicProfileError.stateMismatch("cached fixture is missing its digest")
        }
        let data = Data(repeating: seed, count: bytes)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial, options: .atomic)
        let cas = CASManager(paths: paths)
        try cas.commit(partialAt: partial, sha256: digest)
        guard let verify = cas.verifyRecord(for: digest) else {
            throw DeterministicProfileError.stateMismatch("CAS verify record is missing")
        }
        try localStore.connection.execute(
            """
            INSERT INTO cache_objects
                (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            params: [
                digest, bytes, Self.timestampString, Self.timestampString,
                verify.size, Int(verify.inode), Int(verify.mtime * 1_000)
            ]
        )
    }

    private func scalarCount(_ sql: String) -> Int {
        ((try? localStore.connection.query(sql) { row in row.int(0) ?? 0 }) ?? [0]).first ?? 0
    }

    private func expectation(
        catalogue: Int,
        favorites: Int = 0,
        collections: Int = 0,
        members: Int = 0,
        positions: [String] = [],
        queue: Int = 0,
        queueStates: Set<QueueItemState> = [],
        pinned: Set<String> = [],
        cached: Int = 0,
        quota: QuotaPolicy = .defaultPolicy
    ) -> DeterministicProfileExpectation {
        DeterministicProfileExpectation(
            catalogueCount: catalogue,
            favoriteCount: favorites,
            collectionCount: collections,
            collectionMemberCount: members,
            collectionPositions: positions,
            queueCount: queue,
            queueStates: queueStates,
            pinnedAssetSetIDs: pinned,
            cachedObjectCount: cached,
            quotaPolicy: quota
        )
    }

    fileprivate static func nextQueueID() -> String {
        queueSequence += 1
        return String(format: "00000000-0000-7000-8000-%012d", 300 + queueSequence)
    }

    private static let collectionID = "00000000-0000-7000-8000-000000000200"
    private static let quotaAssetID = "00000000-0000-7000-8000-000000000041"
    private static let quotaDownloadAssetID = "00000000-0000-7000-8000-000000000042"
    private static let storageAssetID = "00000000-0000-7000-8000-000000000073"
    private static let saveRestorableAssetID = "00000000-0000-7000-8000-000000000091"
    private static let saveOnlyCopyAssetID = "00000000-0000-7000-8000-000000000092"
    private static let saveDivergedAssetID = "00000000-0000-7000-8000-000000000093"
    private static let timestampString = "2026-01-01T00:00:00Z"

    private static func catalogueEntries(count: Int) -> [CatalogueEntry] {
        (1...count).map { entry(
            id: String(format: "00000000-0000-7000-8000-%012d", $0),
            title: "Synthetic Game \($0)",
            seed: UInt8($0)
        ) }
    }

    private static func entry(id: String, title: String, seed: UInt8) -> CatalogueEntry {
        let data = Data(repeating: seed, count: 32)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CatalogueEntry(
            id: id,
            system: "synthetic-system",
            displayTitle: title,
            tags: ["fixture": "deterministic"],
            members: [
                AssetMember(
                    ordinal: 0,
                    role: "fixture",
                    required: true,
                    sha256: digest,
                    size: data.count,
                    name: "synthetic-\(seed).bin"
                )
            ]
        )
    }
}
#endif
