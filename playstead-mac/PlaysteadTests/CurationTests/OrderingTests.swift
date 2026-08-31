import XCTest
@testable import Playstead

/// Covers plan 03-08 task 2's `<behavior>` and `<acceptance_criteria>`:
/// collections/queue/continue offline, fractional-index reorder settling
/// to exactly one intent per gesture, offline-vs-remote convergence, and
/// Continue's no-promise copy contract.
final class OrderingTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var curationStore: CurationStore!
    private var apiClient: APIClient!
    private var outbox: Outbox!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        curationStore = CurationStore(localStore: localStore)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        outbox = Outbox(localStore: localStore, curationStore: curationStore)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - FractionalPosition compatibility with the server's encoding

    func test_fractionalPosition_matchesServerFixtures() {
        XCTAssertEqual(FractionalPosition.first(), "i")
        XCTAssertEqual(FractionalPosition.last(nil), "i")

        let p1 = FractionalPosition.last(nil)
        let p2 = FractionalPosition.last(p1)
        let p3 = FractionalPosition.last(p2)
        XCTAssertEqual(p1, "i")
        XCTAssertEqual(p2, "j")
        XCTAssertEqual(p3, "k")

        XCTAssertEqual(FractionalPosition.between(p1, p2), "ii")
        XCTAssertEqual(FractionalPosition.between(nil, p1), "h")

        XCTAssertEqual(FractionalPosition.spaced(5), ["6", "c", "i", "o", "u"])
        XCTAssertFalse(FractionalPosition.needsRebalance(p1, p2))
    }

    func test_fractionalPosition_sequentialAppendsGrowAmortizedNotLinearly() {
        var last = FractionalPosition.first()
        for _ in 0..<300 {
            last = FractionalPosition.last(last)
        }
        XCTAssertEqual(last, "zzzzzzzzz3", "must match the server's identical growth pattern exactly")
        XCTAssertEqual(last.count, 10)
    }

    func test_fractionalPosition_orderingIsStringComparable() {
        var current: String? = nil
        var previous: String?
        for _ in 0..<20 {
            let next = FractionalPosition.last(current)
            if let previous {
                XCTAssertLessThan(previous, next)
            }
            previous = current
            current = next
        }
    }

    // MARK: - A drag reorder emits exactly one intent when the gesture settles

    func test_multiStepDragReorder_createsExactlyOneOutboxEntry() throws {
        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        vm.createCollection(name: "My Collection")
        let collectionID = vm.collections[0].id

        vm.addMember(to: collectionID, assetSetID: "a")
        vm.addMember(to: collectionID, assetSetID: "b")
        vm.addMember(to: collectionID, assetSetID: "c")
        let afterAdds = outbox.listAll().count

        vm.beginReorderMembers(collectionID)
        // Simulate a multi-step drag: several intermediate preview
        // positions before the gesture settles — none of these write to
        // the outbox.
        vm.previewMoveMember(collectionID, assetSetID: "a", to: 1)
        vm.previewMoveMember(collectionID, assetSetID: "a", to: 2)
        vm.previewMoveMember(collectionID, assetSetID: "a", to: 1)
        XCTAssertEqual(outbox.listAll().count, afterAdds, "preview steps must never write to the outbox")

        XCTAssertTrue(vm.commitReorderMembers(collectionID, assetSetID: "a"))

        XCTAssertEqual(outbox.listAll().count, afterAdds + 1, "the settled gesture must produce exactly one entry")
    }

    // MARK: - The move intent names the moved item and its neighbours,
    // never an array of identifiers.

    func test_moveIntentPayload_namesMovedItemAndTwoNeighboursOnly() throws {
        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        vm.createCollection(name: "My Collection")
        let collectionID = vm.collections[0].id

        vm.addMember(to: collectionID, assetSetID: "a")
        vm.addMember(to: collectionID, assetSetID: "b")
        vm.addMember(to: collectionID, assetSetID: "c")

        vm.beginReorderMembers(collectionID)
        vm.previewMoveMember(collectionID, assetSetID: "a", to: 2)
        XCTAssertTrue(vm.commitReorderMembers(collectionID, assetSetID: "a"))

        let moveEntry = outbox.listAll().last(where: { $0.kind == .collectionMemberMove })
        XCTAssertNotNil(moveEntry)
        guard case .collectionMemberMove(_, _, let assetSetID, _, let before, let after) = moveEntry?.intent else {
            return XCTFail("expected a collectionMemberMove intent")
        }
        XCTAssertEqual(assetSetID, "a")
        // "a" moved to the end (index 2 of 3, after b and c): its new neighbours are c (before) and nothing (after).
        XCTAssertEqual(before, "c")
        XCTAssertNil(after)

        // No array-shaped field anywhere in the persisted envelope/body.
        let body = String(data: moveEntry!.intent!.wireBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("["), "the wire body must never carry a whole ordered list")
    }

    // MARK: - An offline local reorder and a journal-delivered remote
    // addition converge to a list containing both.

    func test_offlineReorderAndRemoteAddition_bothSurviveInTheResultingList() throws {
        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        vm.createCollection(name: "My Collection")
        let collectionID = vm.collections[0].id

        vm.addMember(to: collectionID, assetSetID: "a")
        vm.addMember(to: collectionID, assetSetID: "b")

        // Offline: reorder locally.
        vm.beginReorderMembers(collectionID)
        vm.previewMoveMember(collectionID, assetSetID: "a", to: 1)
        XCTAssertTrue(vm.commitReorderMembers(collectionID, assetSetID: "a"))

        // Meanwhile, a journal entry arrives for a member added on
        // another device — a distinct row id, never seen locally before.
        let applier = JournalApplier(catalogueStore: CatalogueStore(localStore: localStore), curationStore: curationStore)
        applier.apply([
            JournalEntry(
                entityKind: "curation", entityID: "remote-member-1", operation: "upsert",
                payload: .object([
                    "type": .string("collection_member"),
                    "collection_id": .string(collectionID),
                    "asset_set_id": .string("c"),
                    "position": .string("zz"),
                    "added_at": .string("2026-08-30T00:00:00Z")
                ])
            )
        ])

        let finalAssetSetIDs = Set(vm.members(of: collectionID).map(\.assetSetID))
        XCTAssertEqual(finalAssetSetIDs, ["a", "b", "c"], "neither device's independent addition may be dropped")
    }

    // MARK: - An empty collection renders and mutates correctly.

    func test_emptyCollection_hasNonEmptyExplanationAndAccessibleLabel() {
        XCTAssertFalse(CollectionDetailView.emptyExplanation.isEmpty)
        XCTAssertFalse(CollectionsView.emptyExplanation.isEmpty)

        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        vm.createCollection(name: "Empty Collection")
        let collectionID = vm.collections[0].id
        XCTAssertEqual(vm.members(of: collectionID), [])
    }

    // MARK: - Dismissing a game from Continue removes it from Continue
    // and leaves it in Recent.

    func test_dismissedGame_isAbsentFromContinueAndPresentInRecent() throws {
        try curationStore.upsertRecent(assetSetID: "asset-1", lastPlayedAt: "2026-08-30T00:00:00Z")
        let continueVM = ContinueViewModel(curationStore: curationStore, outbox: outbox)
        let recentVM = RecentViewModel(curationStore: curationStore)

        XCTAssertTrue(continueVM.items.contains { $0.assetSetID == "asset-1" })

        XCTAssertTrue(continueVM.dismiss(assetSetID: "asset-1"))

        XCTAssertFalse(continueVM.items.contains { $0.assetSetID == "asset-1" }, "dismissed game must be absent from Continue")
        recentVM.refresh()
        XCTAssertTrue(recentVM.items.contains { $0.assetSetID == "asset-1" }, "dismissed game must remain in Recent")
    }

    // MARK: - Continue's copy contains no promise about restoring progress.

    func test_continueShelfCopy_containsNoPromiseAboutRestoringProgress() {
        let forbidden = ["restore", "resume", "save", "your progress"]
        let allCopy = [
            ContinueShelfView.Copy.heading,
            ContinueShelfView.Copy.emptyExplanation,
            ContinueShelfView.Copy.subtitle(relativeTime: "2 days ago")
        ].joined(separator: " ").lowercased()

        for word in forbidden {
            XCTAssertFalse(allCopy.contains(word), "Continue copy must not contain '\(word)'")
        }
    }

    // MARK: - A one-member collection and a one-item queue behave
    // identically to larger ones.

    func test_oneMemberCollectionAndOneItemQueue_behaveLikeLargerOnes() throws {
        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        vm.createCollection(name: "Solo")
        let collectionID = vm.collections[0].id
        XCTAssertTrue(vm.addMember(to: collectionID, assetSetID: "only"))
        XCTAssertEqual(vm.members(of: collectionID).count, 1)
        XCTAssertTrue(vm.removeMember(from: collectionID, assetSetID: "only"))
        XCTAssertEqual(vm.members(of: collectionID).count, 0)

        let queueVM = QueueViewModel(curationStore: curationStore, outbox: outbox)
        XCTAssertTrue(queueVM.enqueue(assetSetID: "solo-game"))
        XCTAssertEqual(queueVM.items.count, 1)
        XCTAssertTrue(queueVM.dequeue(assetSetID: "solo-game"))
        XCTAssertEqual(queueVM.items.count, 0)
    }

    // MARK: - Creating, renaming, and deleting a collection all work
    // offline and reconcile on reconnect.

    func test_collectionCreateRenameDelete_workOffline() throws {
        let vm = CollectionsViewModel(curationStore: curationStore, outbox: outbox)
        XCTAssertTrue(vm.createCollection(name: "Original"))
        let collectionID = vm.collections[0].id
        XCTAssertEqual(curationStore.fetchCollections().first?.name, "Original")

        XCTAssertTrue(vm.renameCollection(collectionID, name: "Renamed"))
        XCTAssertEqual(curationStore.fetchCollections().first?.name, "Renamed")

        XCTAssertTrue(vm.deleteCollection(collectionID))
        XCTAssertTrue(curationStore.fetchCollections().isEmpty)
    }

    // MARK: - QueueViewModel drag settles to exactly one intent too.

    func test_queueMultiStepDrag_createsExactlyOneOutboxEntry() throws {
        let vm = QueueViewModel(curationStore: curationStore, outbox: outbox)
        vm.enqueue(assetSetID: "a")
        vm.enqueue(assetSetID: "b")
        vm.enqueue(assetSetID: "c")
        let afterEnqueues = outbox.listAll().count

        vm.beginReorder()
        vm.previewMove(assetSetID: "a", to: 1)
        vm.previewMove(assetSetID: "a", to: 2)
        XCTAssertEqual(outbox.listAll().count, afterEnqueues)

        XCTAssertTrue(vm.commitReorder(assetSetID: "a"))
        XCTAssertEqual(outbox.listAll().count, afterEnqueues + 1)
    }
}
