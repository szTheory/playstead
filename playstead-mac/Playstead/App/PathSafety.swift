import Foundation
import os

/// A value that arrived from the paired server and was about to be used
/// as a filesystem path component failed validation.
///
/// These are deliberately loud, typed errors rather than a silent
/// normalisation: an attacker-controlled string that does not match the
/// shape this client expects is evidence of a compromised or spoofed
/// server, not something to quietly repair into a "close enough" path.
enum PathSafetyError: Error, Equatable, CustomStringConvertible {
    /// `sha256` was not a 64-character lowercase hex digest.
    case invalidDigest(String)
    /// A declared member filename was not a safe, single path component.
    case unsafeFilename(String)

    var description: String {
        switch self {
        case .invalidDigest(let value):
            return "invalid sha256 digest (expected 64 lowercase hex characters): \(Self.redact(value))"
        case .unsafeFilename(let value):
            return "unsafe declared filename (expected a single path component): \(Self.redact(value))"
        }
    }

    /// Bounds an attacker-controlled string before it reaches a log line.
    private static func redact(_ value: String) -> String {
        value.count <= 128 ? value : String(value.prefix(128)) + "…"
    }
}

/// The single place this client decides whether a server-supplied string
/// may become part of a local filesystem path (CR-01, CR-02).
///
/// The client's trust boundary is the paired server's JSON: `sha256` and
/// `name` on every `AssetMember` arrive verbatim from `/api/v1/snapshot`
/// and `/api/v1/changes`. Both are used to build paths under the cache
/// root, and this app intentionally ships **without** App Sandbox (see
/// `Playstead.entitlements`, which sets `com.apple.security.app-sandbox`
/// to `false` so it can launch a child emulator process) — so there is no
/// OS-level containment behind a bad path. Validation happens twice, on
/// purpose:
///
/// 1. **At ingest** — `CatalogueEntry`'s decoder drops any member whose
///    digest or name fails these checks, so an invalid value never
///    reaches the cache layer at all.
/// 2. **At path construction** — `AppPaths.objectURL(for:)`,
///    `AppPaths.partialURL(for:)` and `LaunchMaterializer` re-validate and
///    throw, so a value that somehow bypassed ingest still cannot resolve
///    out of tree.
enum PathSafety {
    private static let logger = Logger(subsystem: "dev.playstead.mac", category: "path-safety")

    /// A well-formed content digest: exactly 64 characters, each one of
    /// `0-9a-f`. Uppercase is rejected too — the CAS layout is derived
    /// from the digest string itself, so two spellings of the same digest
    /// would be two different cache objects.
    ///
    /// This is an allowlist, not a traversal blocklist: anything that is
    /// not exactly this shape is refused, which rules out `..`, `/`, NUL,
    /// Unicode look-alikes and every other encoding trick by construction.
    static func isValidDigest(_ sha256: String) -> Bool {
        guard sha256.utf8.count == 64 else { return false }
        for byte in sha256.utf8 {
            let isDigit = byte >= 0x30 && byte <= 0x39      // 0-9
            let isLowerHex = byte >= 0x61 && byte <= 0x66   // a-f
            guard isDigit || isLowerHex else { return false }
        }
        return true
    }

    /// Returns `sha256` unchanged if it is a well-formed digest, and
    /// throws `PathSafetyError.invalidDigest` otherwise.
    @discardableResult
    static func validatedDigest(_ sha256: String) throws -> String {
        guard isValidDigest(sha256) else {
            throw PathSafetyError.invalidDigest(sha256)
        }
        return sha256
    }

    /// A safe *bare* filename: a single path component that cannot escape
    /// the directory it is appended to.
    ///
    /// Rejects: the empty string, `.` and `..`, anything containing a
    /// path separator or a NUL byte, anything longer than a POSIX name
    /// (255 bytes), and any name whose own `lastPathComponent` differs
    /// from itself (which catches trailing-slash and multi-component
    /// spellings). Leading dots are otherwise allowed — a hidden file is
    /// contained, and rejecting it would be normalisation, not safety.
    static func isSafeFilename(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        guard name.utf8.count <= 255 else { return false }
        guard !name.contains("/"), !name.contains("\0") else { return false }
        // Belt and braces: whatever Foundation itself considers the last
        // component must be the whole string.
        guard (name as NSString).lastPathComponent == name else { return false }
        return true
    }

    /// Returns `name` unchanged if it is a safe bare filename, and throws
    /// `PathSafetyError.unsafeFilename` otherwise.
    @discardableResult
    static func validatedFilename(_ name: String) throws -> String {
        guard isSafeFilename(name) else {
            throw PathSafetyError.unsafeFilename(name)
        }
        return name
    }

    /// Records a rejected server-supplied value. Ingest drops the
    /// offending member rather than failing the whole catalogue page (an
    /// older client must stay usable against a newer server), so this log
    /// line is the only evidence that a drop happened — it must never be
    /// silent.
    static func logRejection(_ error: PathSafetyError, context: String) {
        logger.error("rejected server-supplied value in \(context, privacy: .public): \(error.description, privacy: .public)")
    }
}
