import Foundation

struct MetadataProviderPreview: Decodable, Equatable, Sendable {
    let provider: String
    let enabled: Bool
    let revision: Int
    let disclosureRevision: String
    let queryPreview: String
    let system: String
    let titleWarning: String?
    let credentialsReady: Bool
    let attribution: String
    let termsURL: String
    let imageFetchAllowed: Bool
    let cacheAgeDays: Int

    enum CodingKeys: String, CodingKey {
        case provider, enabled, revision, system, attribution
        case disclosureRevision = "disclosure_revision"
        case queryPreview = "query_preview"
        case titleWarning = "title_warning"
        case credentialsReady = "credentials_ready"
        case termsURL = "terms_url"
        case imageFetchAllowed = "image_fetch_allowed"
        case cacheAgeDays = "cache_age_days"
    }
}

struct MetadataProviderEvidence: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let externalID: Int
    let title: String
    let system: String
    let confidence: String
    let matchKind: String
    let provider: String
    let attribution: String
    let termsURL: String
    let cacheExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, system, confidence, provider, attribution
        case externalID = "external_id"
        case matchKind = "match_kind"
        case termsURL = "terms_url"
        case cacheExpiresAt = "cache_expires_at"
    }
}

struct MetadataPreparationEstimate: Decodable, Equatable, Sendable {
    let mode: String
    let requests: Int
    let bytes: Int
    let storage: Int

    enum CodingKeys: String, CodingKey { case mode, requests, bytes, storage }
}

struct MetadataPreparationJob: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let assetSetID: String
    let state: String
    let progress: JSONValue
    let lastError: String?
    let retryAfterAt: String?

    enum CodingKeys: String, CodingKey {
        case id, state, progress
        case assetSetID = "asset_set_id"
        case lastError = "last_error"
        case retryAfterAt = "retry_after_at"
    }
}

struct MetadataPrivateMediaReceipt: Decodable, Equatable, Sendable {
    let id: String
    let assetSetID: String
    let originalSHA256: String
    let originalSizeBytes: Int
    let originalMIME: String
    let derivedSHA256: String?
    let derivedSizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case assetSetID = "asset_set_id"
        case originalSHA256 = "original_sha256"
        case originalSizeBytes = "original_size_bytes"
        case originalMIME = "original_mime"
        case derivedSHA256 = "derived_sha256"
        case derivedSizeBytes = "derived_size_bytes"
    }
}

struct MetadataCacheSnapshot: Equatable, Sendable {
    let budgetBytes: Int
    let usedBytes: Int
    let pinnedItems: Int
    let expiringItems: Int
    let reclaimableBytes: Int
    var serverBudgetBytes: Int = 1_073_741_824
    var serverUsedBytes: Int = 0
    var serverReclaimableBytes: Int = 0
}

struct MetadataServerCacheUsage: Decodable, Sendable {
    let usedBytes: Int
    let budgetBytes: Int
    let reclaimableBytes: Int
    enum CodingKeys: String, CodingKey {
        case usedBytes = "used_bytes"
        case budgetBytes = "budget_bytes"
        case reclaimableBytes = "reclaimable_bytes"
    }
}
