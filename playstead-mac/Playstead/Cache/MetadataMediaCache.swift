import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MetadataMediaCacheError: Error, Equatable {
    case invalidIdentity
    case digestMismatch
    case unsupportedOrUnsafeImage
    case expired
    case capacityExceeded
}

/// Device-local derived artwork cache. Bytes enter only from an already
/// authorized API response; this type never accepts provider URLs.
actor MetadataMediaCache {
    static let byteLimit = 512 * 1024 * 1024
    static let lowWaterBytes = 128 * 1024 * 1024
    static let maxObjectBytes = 20 * 1024 * 1024
    static let maxDimension = 8192
    static let maxPixels = 40_000_000

    private struct Entry {
        let url: URL
        let size: Int
        let digest: String
        let expiresAt: Date?
        let pinned: Bool
        var accessedAt: Date
    }

    private let root: URL
    private let localStore: LocalStore?
    private let byteLimit: Int
    private let lowWaterBytes: Int
    private var entries: [String: Entry] = [:]

    init(
        root: URL,
        localStore: LocalStore? = nil,
        byteLimit: Int = MetadataMediaCache.byteLimit,
        lowWaterBytes: Int = MetadataMediaCache.lowWaterBytes
    ) {
        self.root = root
        self.localStore = localStore
        self.byteLimit = max(1, byteLimit)
        self.lowWaterBytes = max(0, min(lowWaterBytes, byteLimit))
        restoreIndex()
    }

    func store(
        _ data: Data,
        mediaID: String,
        expectedSHA256: String,
        expiresAt: Date? = nil,
        pinned: Bool = false,
        now suppliedNow: Date? = nil
    ) async throws -> URL {
        guard !mediaID.isEmpty, mediaID.utf8.count <= 256,
              expectedSHA256.count == 64, expectedSHA256.allSatisfy(\.isHexDigit) else {
            throw MetadataMediaCacheError.invalidIdentity
        }
        guard data.count <= Self.maxObjectBytes else { throw MetadataMediaCacheError.capacityExceeded }
        guard Self.sha256(data) == expectedSHA256.lowercased() else { throw MetadataMediaCacheError.digestMismatch }
        let safeImage = await Task.detached(priority: .utility) { Self.isSafeStaticImage(data) }.value
        guard safeImage else { throw MetadataMediaCacheError.unsupportedOrUnsafeImage }
        try Task.checkCancellation()
        // Resolve the production clock after asynchronous decoding so a
        // deadline crossed during validation cannot authorize publication.
        let now = suppliedNow ?? Date()
        let key = Self.sha256(Data(mediaID.utf8))
        let old = entries[key]
        let effectiveExpiry: Date?
        if let oldExpiry = old?.expiresAt, let expiresAt { effectiveExpiry = min(oldExpiry, expiresAt) }
        else { effectiveExpiry = old?.expiresAt ?? expiresAt }
        if let effectiveExpiry, effectiveExpiry <= now { throw MetadataMediaCacheError.expired }
        let target = root.appendingPathComponent(key, isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projected = entries.filter { $0.key != key }.values.reduce(0) { $0 + $1.size } + data.count
        if projected > byteLimit {
            let reclaimTarget = max(0, byteLimit - lowWaterBytes)
            for (candidateKey, candidate) in entries.filter({ !$0.value.pinned }).sorted(by: {
                let leftExpired = $0.value.expiresAt.map { $0 <= now } ?? false
                let rightExpired = $1.value.expiresAt.map { $0 <= now } ?? false
                if leftExpired != rightExpired { return leftExpired }
                return $0.value.accessedAt < $1.value.accessedAt
            }) {
                try? FileManager.default.removeItem(at: candidate.url)
                entries.removeValue(forKey: candidateKey)
                try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [candidateKey])
                if entries.values.reduce(0, { $0 + $1.size }) + data.count <= reclaimTarget { break }
            }
        }
        guard entries.filter({ $0.key != key }).values.reduce(0, { $0 + $1.size }) + data.count <= byteLimit else {
            throw MetadataMediaCacheError.capacityExceeded
        }
        try data.write(to: target, options: .atomic)
        let entry = Entry(url: target, size: data.count, digest: Self.sha256(data), expiresAt: effectiveExpiry, pinned: pinned, accessedAt: now)
        do {
            try persist(entry, key: key)
        } catch {
            try? FileManager.default.removeItem(at: target)
            entries.removeValue(forKey: key)
            try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
            throw error
        }
        entries[key] = entry
        if let old, old.url != target { try? FileManager.default.removeItem(at: old.url) }
        return target
    }

    func cachedData(mediaID: String, now: Date = Date()) throws -> Data? {
        let key = Self.sha256(Data(mediaID.utf8))
        guard var entry = entries[key] else { return nil }
        if let expiry = entry.expiresAt, expiry <= now {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
            try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
            throw MetadataMediaCacheError.expired
        }
        guard let data = try? Data(contentsOf: entry.url), Self.sha256(data) == entry.digest,
              data.count == entry.size else {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
            try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
            return nil
        }
        entry.accessedAt = now
        entries[key] = entry
        try? persist(entry, key: key)
        return data
    }

    func usedBytes() -> Int { entries.values.reduce(0) { $0 + $1.size } }

    func pinnedCount() -> Int { entries.values.filter(\.pinned).count }

    func expiringCount(now: Date = Date()) -> Int {
        entries.values.filter { $0.expiresAt.map { $0 <= now.addingTimeInterval(7 * 24 * 60 * 60) } ?? false }.count
    }

    func reclaimableBytes() -> Int { entries.values.filter { !$0.pinned }.reduce(0) { $0 + $1.size } }

    func reclaimUnpinned() throws {
        for (key, entry) in entries where !entry.pinned {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
            try localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
        }
    }

    func pin(mediaID: String, isPinned: Bool, now: Date = Date()) throws {
        let key = Self.sha256(Data(mediaID.utf8))
        guard var entry = entries[key] else { return }
        entry = Entry(url: entry.url, size: entry.size, digest: entry.digest,
                      expiresAt: entry.expiresAt, pinned: isPinned, accessedAt: now)
        try persist(entry, key: key)
        entries[key] = entry
    }

    func constrainExpiry(mediaID: String, to policyExpiry: Date?, now: Date = Date()) throws {
        guard let policyExpiry else { return }
        let key = Self.sha256(Data(mediaID.utf8))
        guard var entry = entries[key] else { return }
        let expiry = entry.expiresAt.map { min($0, policyExpiry) } ?? policyExpiry
        guard expiry > now else {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
            try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
            throw MetadataMediaCacheError.expired
        }
        entry = Entry(url: entry.url, size: entry.size, digest: entry.digest, expiresAt: expiry,
                      pinned: entry.pinned, accessedAt: entry.accessedAt)
        try persist(entry, key: key)
        entries[key] = entry
    }

    func discard(mediaID: String) {
        let key = Self.sha256(Data(mediaID.utf8))
        guard let entry = entries.removeValue(forKey: key) else { return }
        try? FileManager.default.removeItem(at: entry.url)
        try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
    }

    func cachedURL(mediaID: String, expectedSHA256: String, expectedSize: Int, now: Date = Date()) throws -> URL? {
        guard let data = try cachedData(mediaID: mediaID, now: now) else { return nil }
        guard data.count == expectedSize, Self.sha256(data) == expectedSHA256.lowercased() else {
            let key = Self.sha256(Data(mediaID.utf8))
            if let entry = entries.removeValue(forKey: key) {
                try? FileManager.default.removeItem(at: entry.url)
                try? localStore?.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
            }
            return nil
        }
        return entries[Self.sha256(Data(mediaID.utf8))]?.url
    }

    private func restoreIndex() {
        guard let localStore else { return }
        let rows = (try? localStore.connection.query(
            "SELECT media_key, sha256, size, expires_at, pinned, last_accessed_at FROM metadata_media_cache;"
        ) { row in
            (row.string(0) ?? "", row.string(1) ?? "", row.int(2) ?? 0,
             row.string(3), row.int(4) == 1, row.string(5) ?? "")
        }) ?? []
        let now = Date()
        for (key, digest, size, expiryText, pinned, accessText) in rows {
            let url = root.appendingPathComponent(key, isDirectory: false)
            guard key.count == 64, key.allSatisfy(\.isHexDigit), digest.count == 64,
                  digest.allSatisfy(\.isHexDigit), size > 0,
                  let bytes = try? Data(contentsOf: url), bytes.count == size, Self.sha256(bytes) == digest else {
                try? FileManager.default.removeItem(at: url)
                try? localStore.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
                continue
            }
            let expiry = expiryText.flatMap(Self.parseDate)
            if let expiry, expiry <= now {
                try? FileManager.default.removeItem(at: url)
                try? localStore.connection.execute("DELETE FROM metadata_media_cache WHERE media_key = ?;", params: [key])
                continue
            }
            entries[key] = Entry(url: url, size: size, digest: digest, expiresAt: expiry,
                                 pinned: pinned, accessedAt: Self.parseDate(accessText) ?? .distantPast)
        }
    }

    private func persist(_ entry: Entry, key: String) throws {
        guard let localStore else { return }
        try localStore.connection.execute(
            """
            INSERT INTO metadata_media_cache (media_key, sha256, size, expires_at, pinned, last_accessed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(media_key) DO UPDATE SET sha256 = excluded.sha256, size = excluded.size,
                expires_at = excluded.expires_at, pinned = excluded.pinned, last_accessed_at = excluded.last_accessed_at;
            """,
            params: [key, entry.digest, entry.size, entry.expiresAt.map(Self.dateString), entry.pinned ? 1 : 0,
                     Self.dateString(entry.accessedAt)]
        )
    }

    private nonisolated static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private nonisolated static func parseDate(_ value: String) -> Date? {
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]
        ]
        for options in optionSets {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func isSafeStaticImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == UTType.png.identifier as CFString || CGImageSourceGetType(source) == UTType.jpeg.identifier as CFString,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maxDimension, height <= maxDimension,
              width <= maxPixels / height else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }
}
