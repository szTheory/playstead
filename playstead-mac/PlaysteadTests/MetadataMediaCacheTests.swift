import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import Playstead

final class MetadataMediaCacheTests: XCTestCase {
    func testCacheValidatesDigestBoundsOfflineHitExpiryAndPinnedCapacity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        var localStore: LocalStore? = try LocalStore(paths: paths)
        let data = try Self.png()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let cache = MetadataMediaCache(root: paths.metadataMedia, localStore: localStore, byteLimit: data.count * 2 + 2, lowWaterBytes: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let url = try await cache.store(data, mediaID: "cover", expectedSHA256: digest, pinned: true, now: now)
        _ = try await cache.store(data, mediaID: "expiring", expectedSHA256: digest, expiresAt: now.addingTimeInterval(1), now: now)
        let cachedData = try await cache.cachedData(mediaID: "cover")
        XCTAssertEqual(cachedData, data)
        XCTAssertEqual(try Data(contentsOf: url), data)
        localStore?.connection.close()
        localStore = try LocalStore(paths: paths)
        let relaunchedCache = MetadataMediaCache(root: paths.metadataMedia, localStore: localStore, byteLimit: data.count * 2 + 2, lowWaterBytes: 0)
        let restoredUsage = await relaunchedCache.usedBytes()
        let restoredBytes = try await relaunchedCache.cachedData(mediaID: "cover")
        XCTAssertEqual(restoredUsage, data.count * 2, "the SQLite index must restore usage and expiry metadata after relaunch")
        XCTAssertEqual(restoredBytes, data, "verified cache bytes remain usable offline after relaunch")
        do {
            _ = try await relaunchedCache.cachedData(mediaID: "expiring", now: now.addingTimeInterval(2))
            XCTFail("expired provider rights must invalidate cached bytes")
        } catch MetadataMediaCacheError.expired {}
        do {
            _ = try await cache.store(data, mediaID: "wrong", expectedSHA256: String(repeating: "0", count: 64))
            XCTFail("digest mismatch must reject bytes")
        } catch MetadataMediaCacheError.digestMismatch {}
        do {
            _ = try await relaunchedCache.store(data, mediaID: "second", expectedSHA256: digest, pinned: true, now: now)
            _ = try await relaunchedCache.store(data, mediaID: "third", expectedSHA256: digest, pinned: true, now: now)
            XCTFail("pinned data must not be evicted to make room")
        } catch MetadataMediaCacheError.capacityExceeded {}
        let staleURL = try await relaunchedCache.cachedURL(
            mediaID: "cover", expectedSHA256: String(repeating: "0", count: 64), expectedSize: data.count
        )
        XCTAssertNil(staleURL, "a cache entry with a stale server digest must be evicted instead of returned")
        let usageAfterStaleEviction = await relaunchedCache.usedBytes()
        XCTAssertEqual(usageAfterStaleEviction, data.count, "stale media releases its pinned bytes")

        // The production seam fetches only the server's authenticated byte
        // endpoint. Concurrent callers coalesce and every returned byte is
        // size/digest checked before the atomic cache commit.
        let mediaID = "B0F2C538-3272-4F9C-87F8-6ACB900BA804"
        let assetSetID = "7C6C379B-8C15-4C17-BAF3-6D908620155B"
        let credential = PairingCredential(deviceID: "device-test", baseURL: URL(string: "https://sync.test")!, token: "test-token")
        let api = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        StubURLProtocol.reset()
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/metadata/\(assetSetID)/media/\(mediaID)/derived")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return StubURLProtocol.Stub(statusCode: 200, headers: ["Content-Type": "image/png"], body: data)
        }
        let networkCache = MetadataMediaCache(root: paths.metadataMedia, localStore: localStore, byteLimit: data.count * 4, lowWaterBytes: 0)
        let mediaClient = MetadataMediaClient(apiClient: api, cache: networkCache)
        _ = try await networkCache.store(data, mediaID: mediaID, expectedSHA256: digest)
        let usageBeforeExpiredPolicy = await networkCache.usedBytes()
        do {
            _ = try await mediaClient.fetchDerived(
                assetSetID: assetSetID, mediaID: mediaID, sha256: digest, size: data.count,
                expiresAt: Date(timeIntervalSince1970: 1)
            )
            XCTFail("expired policy must reject a cache hit before any media is returned")
        } catch MetadataMediaCacheError.expired {}
        XCTAssertEqual(StubURLProtocol.requestLog.count, 0, "expired policy must reject before network access")
        let usageAfterExpiredPolicy = await networkCache.usedBytes()
        XCTAssertEqual(usageAfterExpiredPolicy, usageBeforeExpiredPolicy - data.count,
                       "expired selected policy discards its cached bytes while retaining other media")
        let expiredPolicyBytes = try await networkCache.cachedData(mediaID: mediaID)
        XCTAssertNil(expiredPolicyBytes)

        let shortenedMediaID = "97F9A6F7-286D-49D6-A95A-D6E3CF0A0B75"
        let policyClock = Date()
        _ = try await networkCache.store(
            data, mediaID: shortenedMediaID, expectedSHA256: digest,
            expiresAt: policyClock.addingTimeInterval(120)
        )
        _ = try await mediaClient.fetchDerived(
            assetSetID: assetSetID, mediaID: shortenedMediaID, sha256: digest, size: data.count,
            expiresAt: policyClock.addingTimeInterval(60)
        )
        do {
            _ = try await networkCache.cachedData(mediaID: shortenedMediaID, now: policyClock.addingTimeInterval(61))
            XCTFail("a selected policy expiry must shorten an already cached object's lifetime")
        } catch MetadataMediaCacheError.expired {}
        XCTAssertEqual(StubURLProtocol.requestLog.count, 0, "expiry propagation on a cache hit must not issue a request")

        async let first = mediaClient.fetchDerived(assetSetID: assetSetID, mediaID: mediaID, sha256: digest, size: data.count, expiresAt: nil)
        async let second = mediaClient.fetchDerived(assetSetID: assetSetID, mediaID: mediaID, sha256: digest, size: data.count, expiresAt: nil)
        let urls = try await [first, second]
        XCTAssertEqual(urls[0], urls[1])
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1, "parallel media reads share one authenticated transfer")
        XCTAssertEqual(try Data(contentsOf: urls[0]), data)
        StubURLProtocol.reset()
    }

    private static func png() throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
