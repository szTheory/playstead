import Foundation

/// A minimally-typed JSON value. `JournalEntry.payload` is decoded into
/// this rather than a fixed struct because one entry's payload shape
/// depends on `entityKind` and (for `curation`) a nested `type`
/// discriminator `JournalApplier` reads at apply time — committing to a
/// concrete shape at decode time would make an unrecognised kind/type a
/// hard decode failure instead of the skip-and-count behaviour this
/// task's `<action>` requires for forward compatibility.
enum JSONValue: Codable, Equatable {
    case string(String)
    /// An integer-valued JSON number, decoded via `Int` (exact up to
    /// 64 bits) rather than `Double` (exact only up to ~2^53) — tried
    /// before `.number` below so a large integer id or counter never
    /// silently round-trips to an off-by-a-few value (P4-WR-006).
    case int(Int)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Re-decodes this value as `T` by round-tripping it through
    /// `JSONEncoder`/`JSONDecoder` — used by `JournalApplier` once it
    /// knows the concrete shape a given `entityKind`/`type` implies.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// One change-journal entry, as returned by `GET /api/v1/changes`
/// (`PlaysteadWeb.Api.V1.ChangesController.render_entry/1`) or embedded
/// in a snapshot page's `entries` array. Every field is required to
/// decode — an entry this client doesn't *understand* (unrecognised
/// `entityKind` or payload `type`) is still a perfectly valid entry to
/// decode; only `JournalApplier` decides whether to skip it.
struct JournalEntry: Decodable, Equatable {
    let entityKind: String
    let entityID: String
    let operation: String
    let payload: JSONValue

    private enum CodingKeys: String, CodingKey {
        case entityKind = "entity_kind"
        case entityID = "entity_id"
        case operation
        case payload
    }
}

/// One page of `GET /api/v1/changes`, matching
/// `PlaysteadWeb.Api.V1.ChangesController.index/2`'s JSON shape exactly.
struct ChangesPage: Decodable {
    let entries: [JournalEntry]
    let cursor: String
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case entries, cursor
        case hasMore = "has_more"
    }
}

/// Sync-specific error cases `SyncEngine` branches on. `cursorExpired` is
/// the one error whose remedy is a full snapshot reset rather than a
/// retry (the server's `410 cursor_expired` problem code, mapped here
/// distinctly from a generic transport/server failure).
enum SyncError: Error, Equatable {
    case cursorExpired
    case cursorInvalid
    case transport
    case decodeFailed
    case notPaired
}

/// Fetches pages of `GET /api/v1/changes`, resuming from a stored
/// `OpaqueCursor`.
struct ChangesClient {
    let apiClient: APIClient

    /// Fetches the next page of changes after `cursor`. Maps the
    /// `cursor_expired`/`cursor_invalid` problem codes to their distinct
    /// `SyncError` cases rather than a generic failure.
    func fetch(after cursor: OpaqueCursor) async throws -> ChangesPage {
        let response: APIResponse
        do {
            response = try await apiClient.get(
                path: "/api/v1/changes",
                queryItems: [URLQueryItem(name: "cursor", value: cursor.rawValue)]
            )
        } catch let error as APIClientError {
            throw Self.map(error)
        } catch {
            throw SyncError.transport
        }

        do {
            return try JSONDecoder().decode(ChangesPage.self, from: response.body)
        } catch {
            throw SyncError.decodeFailed
        }
    }

    static func map(_ error: APIClientError) -> SyncError {
        switch error {
        case .notPaired:
            return .notPaired
        case .server(let apiError) where apiError.code == "cursor_expired":
            return .cursorExpired
        case .server(let apiError) where apiError.code == "cursor_invalid":
            return .cursorInvalid
        case .server:
            return .transport
        case .transport, .invalidResponse:
            return .transport
        }
    }
}
