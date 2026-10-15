import CryptoKit
import Foundation

/// Fetches a server-authorized derived image by its owner-scoped media ID.
/// Provider URLs and provider credentials are deliberately absent from this
/// interface. Concurrent requests for the same profile media ID share one
/// authenticated request and one verified cache write.
actor MetadataMediaClient {
    private let apiClient: APIClient
    private let cache: MetadataMediaCache
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(apiClient: APIClient, cache: MetadataMediaCache) {
        self.apiClient = apiClient
        self.cache = cache
    }

    func fetchDerived(
        assetSetID: String,
        mediaID: String,
        sha256: String,
        size: Int,
        expiresAt: Date?,
        pinned: Bool = false
    ) async throws -> URL {
        guard UUID(uuidString: assetSetID) != nil, UUID(uuidString: mediaID) != nil,
              size > 0, size <= MetadataMediaCache.maxObjectBytes,
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else {
            throw MetadataMediaCacheError.invalidIdentity
        }
        guard expiresAt.map({ $0 > Date() }) ?? true else {
            await cache.discard(mediaID: mediaID)
            throw MetadataMediaCacheError.expired
        }
        do {
            if let local = try await cache.cachedURL(
                mediaID: mediaID, expectedSHA256: sha256, expectedSize: size
            ) {
                try await cache.constrainExpiry(mediaID: mediaID, to: expiresAt)
                try await cache.pin(mediaID: mediaID, isPinned: pinned)
                guard expiresAt.map({ $0 > Date() }) ?? true else { throw MetadataMediaCacheError.expired }
                return local
            }
        } catch MetadataMediaCacheError.expired {
            // Expired provider rights invalidate the old bytes but do not
            // make the still-authorized server media endpoint unusable.
        }
        guard expiresAt.map({ $0 > Date() }) ?? true else {
            await cache.discard(mediaID: mediaID)
            throw MetadataMediaCacheError.expired
        }
        let coalescingKey = "\(assetSetID):\(mediaID):\(sha256.lowercased()):\(size):\(expiresAt?.timeIntervalSince1970 ?? -1)"
        if let task = inFlight[coalescingKey] {
            let url = try await task.value
            guard expiresAt.map({ $0 > Date() }) ?? true else { throw MetadataMediaCacheError.expired }
            try await cache.pin(mediaID: mediaID, isPinned: pinned)
            return url
        }

        let apiClient = self.apiClient
        let cache = self.cache
        let task = Task<URL, Error> {
            let response = try await apiClient.get(
                path: "/api/v1/metadata/\(assetSetID)/media/\(mediaID)/derived"
            )
            guard response.headers["content-type"]?.lowercased().hasPrefix("image/png") == true,
                  response.body.count == size,
                  Self.sha256(response.body) == sha256.lowercased() else {
                throw MetadataMediaCacheError.digestMismatch
            }
            return try await cache.store(
                response.body, mediaID: mediaID, expectedSHA256: sha256,
                expiresAt: expiresAt, pinned: pinned
            )
        }
        inFlight[coalescingKey] = task
        defer { inFlight.removeValue(forKey: coalescingKey) }
        let url = try await task.value
        guard expiresAt.map({ $0 > Date() }) ?? true else { throw MetadataMediaCacheError.expired }
        return url
    }

    func usedBytes() async -> Int { await cache.usedBytes() }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
