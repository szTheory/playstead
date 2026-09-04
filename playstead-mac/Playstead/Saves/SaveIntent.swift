import Foundation

/// The two divergence-resolution mutations this client can enqueue --
/// mirrors the server's `resolve_divergence/4` (append a resolution) and
/// `acknowledge_divergence/3` ("Keep both") one-for-one (plan 04-05),
/// and mirrors `CurationIntentKind`'s shape (a persisted `kind` string,
/// with an `unknown` fallback for a future kind this build doesn't
/// recognise).
enum SaveIntentKind: String, Codable, Equatable {
    case unknown
    case chooseSide = "save_choose_side"
    case acknowledgeFork = "save_acknowledge_fork"
}

/// The wire-and-storage envelope for one `SaveIntent` -- what actually
/// gets persisted as `save_outbox_entries.payload_json`, following
/// `CurationIntentEnvelope`'s precedent exactly.
struct SaveIntentEnvelope: Codable, Equatable {
    let kind: SaveIntentKind
    let saveLineID: String
    var chosenRevisionID: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case saveLineID = "save_line_id"
        case chosenRevisionID = "chosen_revision_id"
    }
}

/// One save-fork resolution mutation. `chosenRevisionID` on
/// `.chooseSide` is the field the server calls `chosen_head_id`
/// (`POST /api/v1/saves/lines/:id/resolve`); `.acknowledgeFork` carries
/// no body (`POST .../acknowledge`).
enum SaveIntent: Equatable {
    case chooseSide(saveLineID: String, chosenRevisionID: String)
    case acknowledgeFork(saveLineID: String)

    var kind: SaveIntentKind {
        switch self {
        case .chooseSide: return .chooseSide
        case .acknowledgeFork: return .acknowledgeFork
        }
    }

    var saveLineID: String {
        switch self {
        case .chooseSide(let saveLineID, _): return saveLineID
        case .acknowledgeFork(let saveLineID): return saveLineID
        }
    }

    var httpMethod: String { "POST" }

    var path: String {
        switch self {
        case .chooseSide(let saveLineID, _): return "/api/v1/saves/lines/\(saveLineID)/resolve"
        case .acknowledgeFork(let saveLineID): return "/api/v1/saves/lines/\(saveLineID)/acknowledge"
        }
    }

    var wireBody: Data? {
        switch self {
        case .chooseSide(_, let chosenRevisionID):
            return try? JSONEncoder().encode(["chosen_head_id": chosenRevisionID])
        case .acknowledgeFork:
            return nil
        }
    }

    var envelope: SaveIntentEnvelope {
        switch self {
        case .chooseSide(let saveLineID, let chosenRevisionID):
            return SaveIntentEnvelope(kind: kind, saveLineID: saveLineID, chosenRevisionID: chosenRevisionID)
        case .acknowledgeFork(let saveLineID):
            return SaveIntentEnvelope(kind: kind, saveLineID: saveLineID, chosenRevisionID: nil)
        }
    }

    /// Reconstructs a `SaveIntent` from a persisted envelope -- `nil` if
    /// the envelope is missing a field this kind requires, or if `kind`
    /// is `.unknown` (a future kind this build doesn't recognise), same
    /// guard-not-force-unwrap discipline as `CurationIntent.from(_:)`.
    static func from(_ envelope: SaveIntentEnvelope) -> SaveIntent? {
        switch envelope.kind {
        case .chooseSide:
            guard let chosenRevisionID = envelope.chosenRevisionID else { return nil }
            return .chooseSide(saveLineID: envelope.saveLineID, chosenRevisionID: chosenRevisionID)
        case .acknowledgeFork:
            return .acknowledgeFork(saveLineID: envelope.saveLineID)
        case .unknown:
            return nil
        }
    }
}
