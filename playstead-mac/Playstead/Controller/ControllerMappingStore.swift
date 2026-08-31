import Foundation

/// Persists one `ControllerMapping` per controller product identifier
/// in `controller_mappings`, so a user's remap follows their specific
/// controller across an application restart (D-14). A controller
/// nobody has remapped yet loads its default mapping with no row ever
/// having been written — a mapping is only persisted the moment a
/// caller actually saves or resets it.
final class ControllerMappingStore {
    private let localStore: LocalStore

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// Loads the persisted mapping for `controllerProductID`, or the
    /// default mapping when none has ever been saved.
    func mapping(forControllerProductID controllerProductID: String) -> ControllerMapping {
        let rows = (try? localStore.connection.query(
            "SELECT mappings_json FROM controller_mappings WHERE controller_product_id = ?;",
            params: [controllerProductID]
        ) { row -> String in row.string(0) ?? "" }) ?? []

        guard
            let json = rows.first, !json.isEmpty,
            let data = json.data(using: .utf8),
            let mapped = try? JSONDecoder().decode([MappedInput].self, from: data)
        else {
            return ControllerMapping.defaultMapping(controllerProductID: controllerProductID)
        }
        return ControllerMapping(controllerProductID: controllerProductID, mappings: mapped)
    }

    /// Persists `mapping`, replacing any prior mapping for the same
    /// controller.
    func save(_ mapping: ControllerMapping) throws {
        let data = try JSONEncoder().encode(mapping.mappings)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        try localStore.connection.execute(
            """
            INSERT INTO controller_mappings (controller_product_id, mappings_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(controller_product_id) DO UPDATE SET
                mappings_json = excluded.mappings_json,
                updated_at = excluded.updated_at;
            """,
            params: [mapping.controllerProductID, json, ISO8601DateFormatter().string(from: Date())]
        )
    }

    /// Resets a controller's mapping to the default and persists that
    /// reset too — D-14 requires reset to both restore and persist the
    /// default, not merely restore it for the current session.
    @discardableResult
    func reset(controllerProductID: String) throws -> ControllerMapping {
        let defaultMapping = ControllerMapping.defaultMapping(controllerProductID: controllerProductID)
        try save(defaultMapping)
        return defaultMapping
    }
}
