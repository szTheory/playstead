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

/// Ingest-time validation of the two server-supplied member fields that
/// later become filesystem path components (CR-01, CR-02).
///
/// This is the client's primary defence, and it sits at the decoder
/// because both server entry points for catalogue data funnel through it:
/// `SnapshotClient` decodes `GET /api/v1/snapshot`, and `JournalApplier`
/// decodes the same `CatalogueEntry` shape out of each `/api/v1/changes`
/// journal payload. A member rejected here never reaches `CatalogueStore`,
/// `DownloadQueue`, `CASManager` or `LaunchMaterializer` at all.
///
/// A bad member is *dropped and logged*, not fatal to the page: failing
/// the whole decode would let one malformed member deny service to an
/// entire catalogue. The surrounding entry survives with its remaining
/// members, so the affected game simply reads as not-yet-cached rather
/// than silently launching something the server did not name.
///
/// Declared in an extension so the compiler still synthesises
/// `CatalogueEntry`'s memberwise initialiser for the call sites that build
/// entries locally (`ReadinessEngine`, tests).
extension CatalogueEntry {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        self.init(
            id: id,
            system: try container.decode(String.self, forKey: .system),
            displayTitle: try container.decode(String.self, forKey: .displayTitle),
            tags: try container.decode([String: String].self, forKey: .tags),
            members: Self.validatedMembers(
                try container.decode([AssetMember].self, forKey: .members),
                assetSetID: id
            )
        )
    }

    /// Drops any member whose non-nil `sha256` is not a 64-character
    /// lowercase hex digest, or whose non-nil `name` is not a safe bare
    /// filename. A `nil` field is not a validation failure — the existing
    /// consumers already skip members missing a digest or a name.
    static func validatedMembers(_ members: [AssetMember], assetSetID: String) -> [AssetMember] {
        members.filter { member in
            do {
                if let sha256 = member.sha256 { try PathSafety.validatedDigest(sha256) }
                if let name = member.name { try PathSafety.validatedFilename(name) }
                return true
            } catch let error as PathSafetyError {
                PathSafety.logRejection(error, context: "catalogue member ordinal \(member.ordinal) of asset set \(assetSetID)")
                return false
            } catch {
                return false
            }
        }
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
