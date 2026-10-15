import Foundation

/// The owner-selected, private description mirrored from the server.
struct MetadataSelection: Codable, Equatable {
    let version: Int
    let type: String
    let assetSetID: String
    let description: String
    let revision: Int
    let deletedAt: String?
    let selections: [String: JSONValue]
    let fieldRevisions: [String: Int]
    let fieldSources: [String: JSONValue]
    let deletedFields: [String: JSONValue]
    let conflicts: [JSONValue]
    let evidence: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case version, type, description, revision
        case assetSetID = "asset_set_id"
        case deletedAt = "deleted_at"
        case selections, conflicts, evidence
        case fieldRevisions = "field_revisions"
        case fieldSources = "field_sources"
        case deletedFields = "deleted_fields"
    }

    init(
        version: Int,
        type: String,
        assetSetID: String,
        description: String,
        revision: Int,
        deletedAt: String?,
        selections: [String: JSONValue] = [:],
        fieldRevisions: [String: Int] = [:],
        fieldSources: [String: JSONValue] = [:],
        deletedFields: [String: JSONValue] = [:],
        conflicts: [JSONValue] = [],
        evidence: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.type = type
        self.assetSetID = assetSetID
        self.description = description
        self.revision = revision
        self.deletedAt = deletedAt
        self.selections = selections
        self.fieldRevisions = fieldRevisions
        self.fieldSources = fieldSources
        self.deletedFields = deletedFields
        self.conflicts = conflicts
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "description"
        assetSetID = try values.decode(String.self, forKey: .assetSetID)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        revision = try values.decode(Int.self, forKey: .revision)
        deletedAt = try values.decodeIfPresent(String.self, forKey: .deletedAt)
        selections = try values.decodeIfPresent([String: JSONValue].self, forKey: .selections) ?? [:]
        fieldRevisions = try values.decodeIfPresent([String: Int].self, forKey: .fieldRevisions) ?? [:]
        fieldSources = try values.decodeIfPresent([String: JSONValue].self, forKey: .fieldSources) ?? [:]
        deletedFields = try values.decodeIfPresent([String: JSONValue].self, forKey: .deletedFields) ?? [:]
        conflicts = try values.decodeIfPresent([JSONValue].self, forKey: .conflicts) ?? []
        evidence = try values.decodeIfPresent([String: JSONValue].self, forKey: .evidence) ?? [:]
    }

    /// Concurrency belongs to a field. The original description-only wire
    /// representation used its document revision before field maps existed.
    func revision(forField field: String) -> Int {
        if let value = fieldRevisions[field] { return value }
        if field == "description", fieldRevisions.isEmpty, selections.isEmpty,
           !description.isEmpty || deletedAt != nil { return revision }
        return 0
    }
}

/// SQLite projection for optional metadata. Callers wrap page, snapshot,
/// and cursor writes in the same LocalStore transaction.
struct MetadataStore {
    static let didChangeNotification = Notification.Name("dev.playstead.metadata-store.changed")
    let localStore: LocalStore

    func upsert(_ selection: MetadataSelection) throws {
        guard selection.version == 1, selection.type == "description",
              !selection.assetSetID.isEmpty, selection.revision >= 0 else {
            throw MetadataStoreError.invalidSelection
        }
        let payload = try JSONEncoder().encode(selection)
        guard let payloadJSON = String(data: payload, encoding: .utf8) else {
            throw MetadataStoreError.invalidSelection
        }
        try localStore.connection.execute(
            """
            INSERT INTO metadata_descriptions (asset_set_id, description, revision, payload_json, deleted_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(asset_set_id) DO UPDATE SET
                description = excluded.description,
                revision = excluded.revision,
                payload_json = excluded.payload_json,
                deleted_at = excluded.deleted_at
            WHERE excluded.revision >= metadata_descriptions.revision;
            """,
            params: [selection.assetSetID, selection.description, selection.revision, payloadJSON, selection.deletedAt]
        )
        NotificationCenter.default.post(name: Self.didChangeNotification, object: localStore)
    }

    func applyOptimistic(assetSetID: String, field: String, value: JSONValue, baseRevision: Int) throws {
        let text = value.stringValue
        guard UUID(uuidString: assetSetID) != nil, baseRevision >= 0, ["title", "description"].contains(field),
              value == .null || text.map({ $0.utf8.count <= 65_536 }) == true else {
            throw MetadataStoreError.invalidSelection
        }
        let current = selection(for: assetSetID)
        var selections = current?.selections ?? [:]
        var fieldRevisions = current?.fieldRevisions ?? [:]
        var fieldSources = current?.fieldSources ?? [:]
        var deletedFields = current?.deletedFields ?? [:]
        if value == .null { selections.removeValue(forKey: field) } else { selections[field] = value }
        fieldRevisions[field] = baseRevision + 1
        fieldSources[field] = .string("user")
        if value == .null { deletedFields[field] = .int(baseRevision + 1) }
        else { deletedFields.removeValue(forKey: field) }
        let conflicts = (current?.conflicts ?? []).filter { conflict in
            guard case .object(let fields) = conflict else { return true }
            return fields["field"]?.stringValue != field
        }
        let description = field == "description" ? (text ?? "") : (current?.description ?? "")
        try upsert(MetadataSelection(
            version: 1, type: "description", assetSetID: assetSetID, description: description,
            revision: max(current?.revision ?? 0, baseRevision) + 1, deletedAt: nil,
            selections: selections, fieldRevisions: fieldRevisions, fieldSources: fieldSources,
            deletedFields: deletedFields, conflicts: conflicts, evidence: current?.evidence ?? [:]
        ))
    }

    func recordConflict(_ conflict: MetadataConflictResponse, assetSetID: String) throws {
        guard !assetSetID.isEmpty, ["title", "description"].contains(conflict.field),
              conflict.currentRevision >= 0 else { throw MetadataStoreError.invalidSelection }
        let current = selection(for: assetSetID)
        var selections = current?.selections ?? [:]
        var revisions = current?.fieldRevisions ?? [:]
        var sources = current?.fieldSources ?? [:]
        var deletedFields = current?.deletedFields ?? [:]
        let currentValue = conflict.currentAlternative["value"] ?? .null
        if currentValue == .null {
            selections.removeValue(forKey: conflict.field)
            deletedFields[conflict.field] = .int(conflict.currentRevision)
        } else {
            selections[conflict.field] = currentValue
            deletedFields.removeValue(forKey: conflict.field)
        }
        revisions[conflict.field] = conflict.currentRevision
        sources[conflict.field] = conflict.currentAlternative["source"] ?? .string("user")
        let record: JSONValue = .object([
            "field": .string(conflict.field),
            "base_revision": .int(conflict.baseRevision),
            "current_revision": .int(conflict.currentRevision),
            "current_alternative": .object(conflict.currentAlternative),
            "incoming_alternative": .object(conflict.incomingAlternative)
        ])
        let conflicts = (current?.conflicts ?? []).filter {
            guard case .object(let fields) = $0 else { return true }
            return fields["field"]?.stringValue != conflict.field
        } + [record]
        let description = conflict.field == "description"
            ? (currentValue.stringValue ?? "") : (current?.description ?? "")
        try storeUnconditionally(MetadataSelection(
            version: 1, type: "description", assetSetID: assetSetID, description: description,
            revision: max(current?.revision ?? 0, conflict.currentRevision), deletedAt: nil,
            selections: selections, fieldRevisions: revisions, fieldSources: sources,
            deletedFields: deletedFields, conflicts: conflicts,
            evidence: current?.evidence ?? [:]
        ))
    }

    private func storeUnconditionally(_ selection: MetadataSelection) throws {
        guard let data = try? JSONEncoder().encode(selection), let payload = String(data: data, encoding: .utf8) else {
            throw MetadataStoreError.invalidSelection
        }
        let existed = self.selection(for: selection.assetSetID) != nil
        try localStore.connection.execute(
            "UPDATE metadata_descriptions SET description = ?, revision = ?, payload_json = ?, deleted_at = ? WHERE asset_set_id = ?;",
            params: [selection.description, selection.revision, payload, selection.deletedAt, selection.assetSetID]
        )
        if !existed { try upsert(selection) }
        else { NotificationCenter.default.post(name: Self.didChangeNotification, object: localStore) }
    }

    func tombstone(assetSetID: String) throws {
        try localStore.connection.execute(
            "UPDATE metadata_descriptions SET deleted_at = COALESCE(deleted_at, CURRENT_TIMESTAMP) WHERE asset_set_id = ?;",
            params: [assetSetID]
        )
        NotificationCenter.default.post(name: Self.didChangeNotification, object: localStore)
    }

    func clearAll() throws {
        try localStore.connection.execute("DELETE FROM metadata_descriptions;")
        NotificationCenter.default.post(name: Self.didChangeNotification, object: localStore)
    }

    func description(for assetSetID: String) -> String? {
        let rows = (try? localStore.connection.query(
            "SELECT description FROM metadata_descriptions WHERE asset_set_id = ? AND deleted_at IS NULL LIMIT 1;",
            params: [assetSetID]
        ) { $0.string(0) }) ?? []
        return rows.first ?? nil
    }

    func selection(for assetSetID: String) -> MetadataSelection? {
        let rows = (try? localStore.connection.query(
            "SELECT payload_json FROM metadata_descriptions WHERE asset_set_id = ? LIMIT 1;",
            params: [assetSetID]
        ) { $0.string(0) }) ?? []
        guard let raw = rows.first ?? nil, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MetadataSelection.self, from: data)
    }
}

enum MetadataStoreError: Error {
    case invalidSelection
}
