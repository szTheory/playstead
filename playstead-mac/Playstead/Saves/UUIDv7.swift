import Foundation

/// Generates RFC 9562 UUIDv7 strings — the format
/// `Playstead.CommandId.cast/1` requires for every `command_id` path
/// parameter (D-20b, D-16). `Foundation.UUID()` produces UUIDv4, which
/// `CommandId.cast/1`'s server-side regex rejects outright, so every
/// caller that mints a `command_id` for a streamed save upload must go
/// through this rather than `UUID().uuidString` — a mistake this type's
/// existence makes structurally hard to repeat.
enum UUIDv7 {
    /// A fresh, lowercase, RFC 9562-formatted UUIDv7 string: a
    /// millisecond Unix timestamp in the first 48 bits, version nibble
    /// `7`, variant bits `10xx`, and cryptographically random fill for
    /// the remaining bits.
    static func generate(now: Date = Date()) -> String {
        let millis = UInt64(now.timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)

        bytes[0] = UInt8((millis >> 40) & 0xFF)
        bytes[1] = UInt8((millis >> 32) & 0xFF)
        bytes[2] = UInt8((millis >> 24) & 0xFF)
        bytes[3] = UInt8((millis >> 16) & 0xFF)
        bytes[4] = UInt8((millis >> 8) & 0xFF)
        bytes[5] = UInt8(millis & 0xFF)

        var random = [UInt8](repeating: 0, count: 10)
        for i in 0..<random.count { random[i] = UInt8.random(in: .min ... .max) }

        bytes[6] = 0x70 | (random[0] & 0x0F) // version nibble 7
        bytes[7] = random[1]
        bytes[8] = 0x80 | (random[2] & 0x3F) // variant bits 10xx
        bytes[9] = random[3]
        bytes[10] = random[4]
        bytes[11] = random[5]
        bytes[12] = random[6]
        bytes[13] = random[7]
        bytes[14] = random[8]
        bytes[15] = random[9]

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let p1 = hex.prefix(8)
        let p2 = hex.dropFirst(8).prefix(4)
        let p3 = hex.dropFirst(12).prefix(4)
        let p4 = hex.dropFirst(16).prefix(4)
        let p5 = hex.dropFirst(20).prefix(12)
        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }
}
