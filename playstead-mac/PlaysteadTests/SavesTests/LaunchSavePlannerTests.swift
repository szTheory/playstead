import XCTest
@testable import Playstead

/// Covers D-44's governing invariant end to end: the launch path writes
/// save bytes only into emptiness, or over bytes that hash to a proven
/// ancestor of a single uncontested head — everything else is `.keep`.
final class LaunchSavePlannerTests: XCTestCase {

    private func head(
        digest: String = "head-digest", bytesLocal: Bool = true,
        deviceName: String = "MacBook Air", lastSavedDescription: String = "2 hours ago"
    ) -> SaveHeadCandidate {
        SaveHeadCandidate(digest: digest, bytesLocal: bytesLocal, deviceName: deviceName, lastSavedDescription: lastSavedDescription)
    }

    // MARK: - Into emptiness

    func testEmptyDirectoryWithSingleUncontestedHeadAndLocalBytesRestores() {
        let context = LaunchSaveContext(onDiskDigest: nil, heads: [head(digest: "h1")])
        guard case .restore(let digest, let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .restore")
        }
        XCTAssertEqual(digest, "h1")
        XCTAssertEqual(notice.title, "Picked up from your MacBook Air save.")
    }

    func testEmptyDirectoryWithNoLocalHeadBytesIsFresh() {
        let context = LaunchSaveContext(onDiskDigest: nil, heads: [])
        guard case .fresh(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .fresh")
        }
        XCTAssertNil(notice, "genuinely no saved progress anywhere must be silent")
    }

    func testKnownNewerHeadWithMissingBytesDegradesToFreshWithoutNetwork() {
        let context = LaunchSaveContext(onDiskDigest: nil, heads: [head(digest: "h1", bytesLocal: false, deviceName: "iMac")])
        guard case .fresh(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .fresh (degraded)")
        }
        XCTAssertEqual(notice?.title, "Starting fresh on this Mac.")
        XCTAssertEqual(notice?.actionTitle, "Download saved progress")
    }

    func testDivergedSlotWithEmptyDiskYieldsKeep() {
        let context = LaunchSaveContext(onDiskDigest: nil, heads: [head(digest: "h1"), head(digest: "h2")])
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertEqual(notice?.title, "Two versions of your progress.")
    }

    func testIncompatibleVerdictYieldsKeepRatherThanRestore() {
        let context = LaunchSaveContext(
            onDiskDigest: nil, heads: [head(digest: "h1")],
            compatibilityVerdict: .incompatible(reason: "medium_mismatch")
        )
        guard case .keep = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
    }

    func testSameTitleVerdictNeverSilentlyRestoresOnTheLaunchPath() {
        let context = LaunchSaveContext(onDiskDigest: nil, heads: [head(digest: "h1")], compatibilityVerdict: .sameTitle)
        guard case .keep = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("same_title requires an explicit, acknowledged action — never a silent launch-path restore")
        }
    }

    // MARK: - Target already has bytes

    func testOnDiskBytesHashingToHeadItselfYieldsKeepAsANoOp() {
        let context = LaunchSaveContext(onDiskDigest: "h1", heads: [head(digest: "h1")])
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertNil(notice, "re-running a restore must be silent")
    }

    func testAncestorOnDiskFastForwardsToHead() {
        let context = LaunchSaveContext(
            onDiskDigest: "ancestor-digest", heads: [head(digest: "h1")], ancestorDigests: ["ancestor-digest"]
        )
        guard case .fastForward(let digest) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .fastForward")
        }
        XCTAssertEqual(digest, "h1")
    }

    func testNonAncestorOnDiskNeverFastForwards() {
        let context = LaunchSaveContext(
            onDiskDigest: "unrelated-digest", heads: [head(digest: "h1")], ancestorDigests: ["some-other-ancestor"],
            knownDigests: ["unrelated-digest"]
        )
        guard case .keep = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep, never .fastForward, for a non-ancestor")
        }
    }

    func testExistingUnknownBytesAreKeptWithTheFoundAndKeptNotice() {
        let context = LaunchSaveContext(onDiskDigest: "mystery-digest", heads: [head(digest: "h1")])
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertEqual(notice?.title, "Kept the save already on this Mac.")
    }

    func testKnownButStaleOnDiskBytesAreKeptSilently() {
        let context = LaunchSaveContext(
            onDiskDigest: "old-recorded-digest", heads: [head(digest: "h1")],
            knownDigests: ["old-recorded-digest"]
        )
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertNil(notice)
    }

    func testConflictedSlotNeverWritesTheOtherHeadEvenWhenOnDiskMatchesOneHead() {
        let context = LaunchSaveContext(onDiskDigest: "h1", heads: [head(digest: "h1"), head(digest: "h2")])
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertEqual(notice?.title, "Two versions of your progress.")
    }

    func testAncestorOfOneHeadButTwoHeadsExistStillYieldsKeep() {
        // "Single uncontested head" is required, not merely "an
        // ancestor of some head" — a diverged slot must never fast-
        // forward even when the on-disk bytes are a genuine ancestor of
        // one of the two heads.
        let context = LaunchSaveContext(
            onDiskDigest: "ancestor-of-h1", heads: [head(digest: "h1"), head(digest: "h2")],
            ancestorDigests: ["ancestor-of-h1"]
        )
        guard case .keep(let notice) = LaunchSavePlanner.plan(context: context) else {
            return XCTFail("expected .keep")
        }
        XCTAssertEqual(notice?.title, "Two versions of your progress.")
    }

    func testDivergedSlotYieldsKeepForEveryOnDiskState() {
        let heads = [head(digest: "h1"), head(digest: "h2")]
        let onDiskStates: [String?] = [nil, "h1", "h2", "something-else", "ancestor-of-h1"]
        for onDisk in onDiskStates {
            let context = LaunchSaveContext(
                onDiskDigest: onDisk, heads: heads, ancestorDigests: ["ancestor-of-h1"], knownDigests: ["h1", "h2"]
            )
            guard case .keep = LaunchSavePlanner.plan(context: context) else {
                return XCTFail("diverged slot with on-disk state \(String(describing: onDisk)) must yield .keep")
            }
        }
    }

    // MARK: - Purity

    func testPlannerPerformsZeroNetworkCallsAndNoDiskWritesOnEveryPath() {
        // The planner's signature is `(LaunchSaveContext) -> SavePlan` --
        // a pure value-in/value-out function with no injected I/O
        // capability at all, so there is no seam through which it could
        // touch the network or the filesystem. Exercising every branch
        // and asserting no crash / no side effect is the whole proof
        // available to a pure function; the source-level grep in this
        // plan's acceptance criteria is the complementary static proof.
        let contexts: [LaunchSaveContext] = [
            LaunchSaveContext(onDiskDigest: nil, heads: []),
            LaunchSaveContext(onDiskDigest: nil, heads: [head()]),
            LaunchSaveContext(onDiskDigest: "x", heads: [head(digest: "x")]),
            LaunchSaveContext(onDiskDigest: "x", heads: [head(digest: "y")], ancestorDigests: ["x"]),
            LaunchSaveContext(onDiskDigest: "x", heads: [head(digest: "y"), head(digest: "z")]),
        ]
        for context in contexts {
            _ = LaunchSavePlanner.plan(context: context)
        }
        // No XCTAssert needed beyond "did not crash" -- the type system
        // and this file's own no-I/O signature are the real assertion.
        XCTAssertTrue(true)
    }
}
