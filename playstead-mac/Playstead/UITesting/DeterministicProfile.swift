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
            let verdict = quotaManager.verdict(forAdditional: 1)
            guard !verdict.allowed, verdict.limitHit == .quota,
                  EvictionPlanner(
                    localStore: localStore,
                    catalogueStore: catalogueStore,
                    pinStore: pinStore,
                    cas: CASManager(paths: paths),
                    paths: paths
                  ).candidates().map(\.id) == [Self.quotaAssetID] else {
                throw DeterministicProfileError.stateMismatch("quota profile did not block and expose one reclaim candidate")
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
        }
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
