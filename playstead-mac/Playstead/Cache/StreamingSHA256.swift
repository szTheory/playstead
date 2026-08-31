import Foundation
import CryptoKit

/// Wraps CryptoKit's incremental `SHA256` for resumable hashing.
///
/// Per D-18 there is no serialized mid-stream hash checkpoint: a crash
/// between a byte write and a state write would desynchronize the
/// state from disk, so the on-disk prefix is always the source of
/// truth and is re-hashed on every resume — `resume(from:)` re-reads an
/// existing partial file from byte zero in bounded chunks rather than
/// trusting any persisted digest. Re-hashing a large prefix at local
/// disk speed is measured in a second or less and is the cheaper side
/// of that trade.
struct StreamingSHA256 {
    private var hasher = SHA256()

    mutating func update(data: Data) {
        hasher.update(data: data)
    }

    mutating func finalizeHex() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Rebuilds hash state by reading `url` from byte zero in
    /// `chunkSize` chunks. Used when a download resumes against an
    /// existing partial file.
    static func resume(from url: URL, chunkSize: Int = 1 << 16) throws -> StreamingSHA256 {
        var streaming = StreamingSHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            streaming.update(data: chunk)
        }
        return streaming
    }
}
