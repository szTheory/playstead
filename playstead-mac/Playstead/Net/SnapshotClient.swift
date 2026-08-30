import Foundation

/// One member (ROM/BIOS/manual/etc.) of a catalogue entry, mirroring the
/// server's frozen `catalogue` payload member view
/// (`Playstead.Catalogue.Payload.member_view/1`).
struct AssetMember: Codable, Equatable {
    let ordinal: Int
    let role: String
    let required: Bool
    let sha256: String?
    let size: Int?
    let name: String?
}

/// One catalogue entry (an `AssetSet`), decoded from
/// `GET /api/v1/snapshot`'s `catalogue` array. Decoding is strict: an
/// unrecognised field is ignored (JSONDecoder's default), but a missing
/// required field is a genuine decode failure — never silently
/// defaulted, since a silently-defaulted title or system would corrupt
/// what the library shell renders.
struct CatalogueEntry: Codable, Equatable, Identifiable {
    let id: String
    let system: String
    let displayTitle: String
    let tags: [String: String]
    let members: [AssetMember]

    private enum CodingKeys: String, CodingKey {
        case id, system, tags, members
        case displayTitle = "display_title"
    }
}

/// The full decoded `GET /api/v1/snapshot` response shape (Playstead.Sync.Snapshot.read/2).
/// This tracer plan only consumes `catalogue`; the other branches
/// (curation, job, cursor/paging) are read and ignored for forward
/// compatibility rather than causing a decode failure.
struct SnapshotResponse: Decodable {
    let catalogue: [CatalogueEntry]
    let cursor: String
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case catalogue, cursor
        case hasMore = "has_more"
    }
}

enum SnapshotClientError: Error {
    case decodeFailed(Error)
}

/// Fetches and decodes `GET /api/v1/snapshot`, then persists the
/// catalogue branch into the local SQLite mirror so the library shell
/// can render it on every subsequent launch without a network round trip.
struct SnapshotClient {
    let apiClient: APIClient
    let localStore: LocalStore

    func fetch() async throws -> [CatalogueEntry] {
        let response = try await apiClient.get(path: "/api/v1/snapshot")

        let decoder = JSONDecoder()
        let snapshot: SnapshotResponse
        do {
            snapshot = try decoder.decode(SnapshotResponse.self, from: response.body)
        } catch {
            throw SnapshotClientError.decodeFailed(error)
        }

        try localStore.replaceCatalogue(snapshot.catalogue)
        return snapshot.catalogue
    }
}
