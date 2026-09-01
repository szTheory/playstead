import SwiftUI
import XCTest
@testable import Playstead

@MainActor
final class StorageContractSnapshotTests: XCTestCase {
    private let downloads = [
        DownloadRow(
            id: "synthetic-download-active",
            assetSetID: "synthetic-active",
            title: "Synthetic Adventure",
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 32 * 1024 * 1024,
            state: .active,
            progressPercent: 42
        ),
        DownloadRow(
            id: "synthetic-download-paused",
            assetSetID: "synthetic-paused",
            title: "Pokémon Überlange 你好 Fixture",
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 64 * 1024 * 1024,
            state: .paused,
            progressPercent: nil
        ),
        DownloadRow(
            id: "synthetic-download-waiting",
            assetSetID: "synthetic-waiting",
            title: "Synthetic Queue Boundary",
            sha256: String(repeating: "c", count: 64),
            sizeBytes: 16 * 1024 * 1024,
            state: .waiting,
            progressPercent: nil
        )
    ]

    private let candidates = [
        EvictionCandidate(
            id: "synthetic-old",
            title: "Synthetic Oldest Copy",
            bytes: 32 * 1024 * 1024,
            lastUsedAt: "2026-01-01T00:00:00Z"
        ),
        EvictionCandidate(
            id: "synthetic-new",
            title: "Synthetic Newer Copy",
            bytes: 16 * 1024 * 1024,
            lastUsedAt: "2026-02-01T00:00:00Z"
        )
    ]

    func testDownloadsQuotaReclaimAndStorageVisualContract() throws {
        XCTAssertEqual(downloads.count, 3)
        XCTAssertEqual(Set(downloads.map(\.state)), [.active, .paused, .waiting])
        XCTAssertEqual(downloads.compactMap(\.progressPercent), [42])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.bytes), [32 * 1024 * 1024, 16 * 1024 * 1024])
        XCTAssertEqual(candidates.reduce(0) { $0 + $1.bytes }, 48 * 1024 * 1024)
        XCTAssertFalse(downloads.map(\.title).contains(where: \.isEmpty))
        XCTAssertLessThanOrEqual(StorageContractSheet.requiredWidth, 1_440)
        XCTAssertLessThanOrEqual(StorageContractSheet.requiredHeight, 1_520)

        try PlaysteadSnapshot.assertContactSheet(
            StorageContractSheet(downloads: downloads, candidates: candidates),
            named: "storage-surfaces",
            pointSize: CGSize(width: 1_440, height: 1_520),
            suite: "StorageContractSnapshotTests"
        )
    }

    func testStorageMotionAndReducedMotionContract() {
        let phases = StorageMotionContract.Phase.allCases
        XCTAssertEqual(phases, [.status, .completion, .eviction])
        XCTAssertEqual(Set(phases).count, 3)

        for phase in phases {
            XCTAssertEqual(
                StorageMotionContract.duration(for: phase, reduceMotion: false),
                0.2,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                StorageMotionContract.duration(for: phase, reduceMotion: true),
                0,
                accuracy: 0.000_001
            )
        }

        let normalProgress = ProgressFillState(percent: 42)
        let reducedProgress = ProgressFillState(percent: 42)
        XCTAssertEqual(normalProgress.fraction, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(reducedProgress.fraction, normalProgress.fraction, accuracy: 0.000_001)
        XCTAssertGreaterThan(reducedProgress.fraction, 0)
    }
}

private struct StorageContractSheet: View {
    static let panelWidth: CGFloat = 680
    static let panelHeight: CGFloat = 440
    static let spacing: CGFloat = DesignTokens.Spacing.lg
    static let outerPadding: CGFloat = DesignTokens.Spacing.lg
    static let titleReserve: CGFloat = 40
    static let requiredWidth = (panelWidth * 2) + spacing + (outerPadding * 2)
    static let requiredHeight = (panelHeight * 3) + (spacing * 3) + (outerPadding * 2) + titleReserve

    let downloads: [DownloadRow]
    let candidates: [EvictionCandidate]

    private let quota = QuotaPolicy(
        quotaBytes: 25 * QuotaPolicy.gibibyte,
        floorBytes: 10 * QuotaPolicy.gibibyte
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Storage surfaces contract")
                    .font(.psDisplay)

                HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                    contractPanel("Downloads — populated") {
                        DownloadsView(
                            rows: downloads,
                            onPause: { _ in },
                            onResume: { _ in },
                            onCancel: { _ in },
                            onMoveUp: { _ in },
                            onMoveDown: { _ in }
                        )
                    }
                    contractPanel("Downloads — honest empty") {
                        DownloadsView(
                            rows: [],
                            onPause: { _ in },
                            onResume: { _ in },
                            onCancel: { _ in },
                            onMoveUp: { _ in },
                            onMoveDown: { _ in }
                        )
                        .dynamicTypeSize(.large)
                    }
                }

                HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                    contractPanel("Quota — floor outranks preference") {
                        QuotaSettingsView(
                            policy: quota,
                            usedBytes: 9 * QuotaPolicy.gibibyte,
                            onSetQuota: { _ in }
                        )
                    }
                    contractPanel("Reclaim — exact candidate bytes") {
                        ReclaimPromptView(
                            limitHit: .quota,
                            shortfallBytes: 48 * 1024 * 1024,
                            canRaiseQuota: true,
                            candidates: candidates.map {
                                ReclaimCandidateRow(id: $0.id, title: $0.title, bytes: $0.bytes)
                            },
                            onRaiseQuota: {},
                            onReclaim: { _ in },
                            onCancel: {}
                        )
                        .dynamicTypeSize(.large)
                    }
                }

                HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                    contractPanel("Storage — removable and protected") {
                        StorageView(
                            totalUsedBytes: 80 * 1024 * 1024,
                            quotaBytes: quota.quotaBytes,
                            floorBytes: quota.floorBytes,
                            candidates: candidates,
                            pinnedGames: [PinnedGameRow(id: "synthetic-pinned", title: "Synthetic Protected Copy")],
                            unreferencedObjects: [
                                UnreferencedObject(sha256: String(repeating: "d", count: 64), bytes: 8 * 1024 * 1024)
                            ],
                            quarantinedPartials: [
                                QuarantinedPartial(path: "/synthetic/quarantine/partial.bin", bytes: 8 * 1024 * 1024)
                            ],
                            onReclaim: { _ in },
                            onRemoveQuarantined: { _ in }
                        )
                    }
                    contractPanel("Storage — honest empty") {
                        StorageView(
                            totalUsedBytes: 0,
                            quotaBytes: quota.quotaBytes,
                            floorBytes: quota.floorBytes,
                            candidates: [],
                            pinnedGames: [],
                            unreferencedObjects: [],
                            quarantinedPartials: [],
                            onReclaim: { _ in },
                            onRemoveQuarantined: { _ in }
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    private func contractPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title).font(.psHeading)
            content()
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .topLeading)
        .background(Color.primary.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.35))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
