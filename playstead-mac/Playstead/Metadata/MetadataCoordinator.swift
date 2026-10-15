import Foundation

/// Thin production coordinator over the paired API and durable local mirror.
/// Mutations that can happen offline enter the existing idempotent outbox.
struct MetadataCoordinator {
    let apiClient: APIClient?
    let metadataStore: MetadataStore
    let outbox: Outbox
    let mediaCache: MetadataMediaCache

    func preview(assetSetID: String) async throws -> MetadataProviderPreview {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.preview(apiClient, assetSetID: assetSetID)
    }

    func consent(assetSetID: String, preview: MetadataProviderPreview, enabled: Bool) async throws {
        guard let apiClient else { throw APIClientError.notPaired }
        try await MetadataAPI.setConsent(apiClient, assetSetID: assetSetID, preview: preview, enabled: enabled)
    }

    func search(assetSetID: String) async throws -> [MetadataProviderEvidence] {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.search(apiClient, assetSetID: assetSetID)
    }

    func estimate(assetSetIDs: [String], mode: String) async throws -> MetadataPreparationEstimate {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.estimate(apiClient, assetSetIDs: assetSetIDs, mode: mode)
    }

    func prepare(assetSetID: String, selectedIDs: [String], estimate: MetadataPreparationEstimate) async throws -> [MetadataPreparationJob] {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.prepare(apiClient, assetSetID: assetSetID, selectedIDs: selectedIDs, estimate: estimate)
    }

    func status(jobID: String) async throws -> MetadataPreparationJob {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.status(apiClient, jobID: jobID)
    }

    func cancel(jobID: String) async throws -> MetadataPreparationJob {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.cancel(apiClient, jobID: jobID)
    }

    func correction(assetSetID: String, field: String, value: JSONValue) throws -> OutboxEntry {
        try outbox.setMetadata(assetSetID: assetSetID, field: field, value: value)
    }

    func select(assetSetID: String, field: String, value: JSONValue) async throws -> MetadataSelection {
        guard let apiClient else { throw APIClientError.notPaired }
        let current = metadataStore.selection(for: assetSetID)
        let selection = try await MetadataAPI.select(apiClient, assetSetID: assetSetID, field: field, value: value,
                                                     baseRevision: current?.revision(forField: field) ?? 0)
        try metadataStore.upsert(selection)
        return selection
    }

    func selectProviderEvidence(assetSetID: String, field: String, evidenceID: String) async throws -> MetadataSelection {
        guard let apiClient else { throw APIClientError.notPaired }
        let current = metadataStore.selection(for: assetSetID)
        let selection = try await MetadataAPI.resetProvider(apiClient, assetSetID: assetSetID, field: field,
                                                             evidenceID: evidenceID,
                                                             baseRevision: current?.revision(forField: field) ?? 0)
        try metadataStore.upsert(selection)
        return selection
    }

    func uploadPrivateMedia(assetSetID: String, bytes: Data, mime: String) async throws -> MetadataPrivateMediaReceipt {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.uploadPrivateMedia(apiClient, assetSetID: assetSetID, bytes: bytes, mime: mime)
    }

    func original(assetSetID: String, mediaID: String) async throws -> Data {
        guard let apiClient else { throw APIClientError.notPaired }
        return try await MetadataAPI.original(apiClient, assetSetID: assetSetID, mediaID: mediaID)
    }

    func selection(assetSetID: String) -> MetadataSelection? { metadataStore.selection(for: assetSetID) }

    func cacheSnapshot() async throws -> MetadataCacheSnapshot {
        guard let apiClient else { throw APIClientError.notPaired }
        let used = await mediaCache.usedBytes()
        let server = try await MetadataAPI.cacheUsage(apiClient)
        return MetadataCacheSnapshot(budgetBytes: MetadataMediaCache.byteLimit, usedBytes: used,
                                     pinnedItems: await mediaCache.pinnedCount(),
                                     expiringItems: await mediaCache.expiringCount(),
                                     reclaimableBytes: await mediaCache.reclaimableBytes(),
                                     serverBudgetBytes: server.budgetBytes,
                                     serverUsedBytes: server.usedBytes,
                                     serverReclaimableBytes: server.reclaimableBytes)
    }

    func reclaimCache() async throws {
        guard let apiClient else { throw APIClientError.notPaired }
        try await mediaCache.reclaimUnpinned()
        _ = try await MetadataAPI.reclaimServerCache(apiClient)
    }
}

extension AppEnvironment {
    var metadataCoordinator: MetadataCoordinator {
        MetadataCoordinator(apiClient: apiClient, metadataStore: metadataStore, outbox: outbox, mediaCache: metadataMediaCache)
    }
}
