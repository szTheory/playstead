import CryptoKit
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Authenticated HTTP operations for optional metadata. Provider credentials
/// never leave the server; the only provider request payload is the exact
/// title/system disclosure shown by the consent screen.
enum MetadataAPI {
    static let disclosureTerms = "Only this game's displayed title and system are sent to IGDB. ROM bytes, filenames, save data, and content hashes are never sent."
    static let maxPrivateMediaBytes = 20 * 1024 * 1024

    static func snapshotSelections(from values: [JSONValue]) -> [JournalEntry] {
        values.compactMap { value in
            guard case .object(let object) = value,
                  let assetSetID = object["asset_set_id"]?.stringValue else { return nil }
            return JournalEntry(
                entityKind: "metadata", entityID: assetSetID,
                operation: object["deleted_at"]?.stringValue == nil ? "upsert" : "tombstone",
                payload: value
            )
        }
    }

    static func preview(_ client: APIClient, assetSetID: String) async throws -> MetadataProviderPreview {
        try decode(await client.get(path: "/api/v1/metadata/\(assetSetID)/provider"))
    }

    /// Asset identity is deliberately supplied separately to avoid deriving
    /// it from provider data or query text.
    static func setConsent(_ client: APIClient, assetSetID: String, preview: MetadataProviderPreview, enabled: Bool) async throws {
        let body: Data?
        let method: String
        if enabled {
            body = try JSONSerialization.data(withJSONObject: [
                "title": preview.queryPreview,
                "system": preview.system,
                "disclosure_revision": preview.disclosureRevision
            ])
            method = "POST"
        } else {
            body = nil
            method = "DELETE"
        }
        let response = try await client.send(method: method, path: "/api/v1/metadata/\(assetSetID)/provider/consent",
                                             body: body, headers: ["Idempotency-Key": UUID().uuidString.lowercased()])
        if !enabled, !response.body.isEmpty,
           let receipt = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
           receipt["enabled"] as? Bool == false,
           let cleanup = receipt["cache_cleanup"] as? [String: Any],
           cleanup["status"] as? String == "failed" {
            throw MetadataAPIError.cacheCleanupPending
        }
    }

    static func search(_ client: APIClient, assetSetID: String) async throws -> [MetadataProviderEvidence] {
        let response = try await client.send(method: "POST", path: "/api/v1/metadata/\(assetSetID)/provider/search",
                                             body: Data("{}".utf8), headers: ["Idempotency-Key": UUID().uuidString.lowercased()])
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload?["results"] ?? [])
        return try JSONDecoder().decode([MetadataProviderEvidence].self, from: data)
    }

    static func estimate(_ client: APIClient, assetSetIDs: [String], mode: String) async throws -> MetadataPreparationEstimate {
        let body = try JSONSerialization.data(withJSONObject: ["selected_asset_set_ids": assetSetIDs, "mode": mode])
        return try decode(await client.send(method: "POST", path: "/api/v1/metadata/provider/enrichment/estimate", body: body))
    }

    static func prepare(_ client: APIClient, assetSetID: String, selectedIDs: [String], estimate: MetadataPreparationEstimate) async throws -> [MetadataPreparationJob] {
        let body = try JSONSerialization.data(withJSONObject: [
            "mode": "prepare", "profile_mode": estimate.mode, "selected_asset_set_ids": selectedIDs,
            "estimate": ["requests": estimate.requests, "bytes": estimate.bytes, "storage": estimate.storage]
        ])
        let response = try await client.send(method: "POST", path: "/api/v1/metadata/\(assetSetID)/provider/enrichment",
                                             body: body, headers: ["Idempotency-Key": UUID().uuidString.lowercased()])
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload?["jobs"] ?? [])
        return try JSONDecoder().decode([MetadataPreparationJob].self, from: data)
    }

    static func status(_ client: APIClient, jobID: String) async throws -> MetadataPreparationJob {
        try decode(await client.get(path: "/api/v1/metadata/provider/enrichment/\(jobID)"))
    }

    static func cancel(_ client: APIClient, jobID: String) async throws -> MetadataPreparationJob {
        try decode(await client.send(method: "DELETE", path: "/api/v1/metadata/provider/enrichment/\(jobID)", body: nil,
                                     headers: ["Idempotency-Key": UUID().uuidString.lowercased()]))
    }

    static func cacheUsage(_ client: APIClient) async throws -> MetadataServerCacheUsage {
        try decode(await client.get(path: "/api/v1/metadata/provider/cache"))
    }

    static func reclaimServerCache(_ client: APIClient) async throws -> MetadataServerCacheUsage {
        try decode(await client.send(method: "POST", path: "/api/v1/metadata/provider/cache/reclaim",
                                     body: Data("{}".utf8), headers: ["Idempotency-Key": UUID().uuidString.lowercased()]))
    }

    static func select(_ client: APIClient, assetSetID: String, field: String, value: JSONValue, baseRevision: Int) async throws -> MetadataSelection {
        let body = try JSONSerialization.data(withJSONObject: ["field": field, "value": jsonObject(value), "base_revision": baseRevision])
        return try decode(await client.send(method: "POST", path: "/api/v1/metadata/\(assetSetID)", body: body,
                                            headers: ["Idempotency-Key": UUID().uuidString.lowercased()]))
    }

    static func resetProvider(_ client: APIClient, assetSetID: String, field: String, evidenceID: String, baseRevision: Int) async throws -> MetadataSelection {
        let body = try JSONSerialization.data(withJSONObject: ["field": field, "evidence_id": evidenceID, "base_revision": baseRevision])
        return try decode(await client.send(method: "POST", path: "/api/v1/metadata/\(assetSetID)/reset-provider", body: body,
                                            headers: ["Idempotency-Key": UUID().uuidString.lowercased()]))
    }

    static func uploadPrivateMedia(_ client: APIClient, assetSetID: String, bytes: Data, mime: String) async throws -> MetadataPrivateMediaReceipt {
        guard bytes.count > 0, bytes.count <= maxPrivateMediaBytes,
              validPrivateMedia(bytes, mime: mime) else { throw MetadataAPIError.invalidPrivateMedia }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let reprDigest = Data("sha-256=:\(Data(SHA256.hash(data: bytes)).base64EncodedString()):".utf8)
        let response = try await client.send(method: "POST", path: "/api/v1/metadata/\(assetSetID)/media", body: bytes,
                                             headers: ["Idempotency-Key": UUID().uuidString.lowercased(),
                                                        "Repr-Digest": String(decoding: reprDigest, as: UTF8.self)],
                                             contentType: mime)
        let receipt = try JSONDecoder().decode(MetadataPrivateMediaReceipt.self, from: response.body)
        guard receipt.originalSHA256 == digest, receipt.originalSizeBytes == bytes.count else { throw MetadataAPIError.receiptMismatch }
        return receipt
    }

    static func original(_ client: APIClient, assetSetID: String, mediaID: String) async throws -> Data {
        try await client.get(path: "/api/v1/metadata/\(assetSetID)/media/\(mediaID)/original").body
    }

    private static func decode<T: Decodable>(_ response: APIResponse) throws -> T {
        try JSONDecoder().decode(T.self, from: response.body)
    }

    private static func jsonObject(_ value: JSONValue) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let value): value
        case .int(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(jsonObject)
        case .object(let values): values.mapValues(jsonObject)
        }
    }

    private static func validPrivateMedia(_ bytes: Data, mime: String) -> Bool {
        if mime == "text/plain" {
            return bytes.count <= 65_536 && String(data: bytes, encoding: .utf8) != nil
        }
        guard ["image/png", "image/jpeg"].contains(mime),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              (mime == "image/png" && type == UTType.png.identifier as CFString ||
               mime == "image/jpeg" && type == UTType.jpeg.identifier as CFString),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width <= 40_000_000 / height else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }
}

enum MetadataAPIError: Error {
    case invalidPrivateMedia
    case receiptMismatch
    case cacheCleanupPending
}
