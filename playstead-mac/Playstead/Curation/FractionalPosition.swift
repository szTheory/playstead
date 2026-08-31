import Foundation

/// Base-36 fractional-index string ordering, producing values compatible
/// with the server's own encoding (`Playstead.Curation.Position`) — a
/// straight Swift port of that module's algorithm, digit for digit, so a
/// client-computed position and a server-computed position for the same
/// gap always compare identically once both sides settle. The client
/// computes the intended position locally so an optimistic reorder is
/// immediate; the server recomputes authoritatively from the named
/// neighbours and returns the settled position through the journal —
/// this module exists only to make that local guess land in the right
/// place, never to be the value of record.
///
/// See `Playstead.Curation.Position`'s moduledoc for the encoding
/// rationale (digits after a decimal point in base 36, compared
/// byte-for-byte exactly like a database index scan).
enum FractionalPosition {
    private static let alphabet: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let base = alphabet.count
    private static let maxPrecision = 6

    private static let charToIndex: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() { map[character] = index }
        return map
    }()

    private static let firstValue = String(alphabet[base / 2])

    /// A position for the first item of an otherwise-empty ordered list.
    static func first() -> String { firstValue }

    /// A position after `currentLast` — `nil` means the list is
    /// currently empty, equivalent to `first()`.
    static func last(_ currentLast: String?) -> String {
        guard let currentLast else { return first() }
        return between(currentLast, nil)
    }

    /// A position strictly between `low` and `high`. Either may be `nil`
    /// to mean "start of the list" / "end of the list" respectively;
    /// both `nil` means "the list is empty" (equivalent to `first()`).
    static func between(_ low: String?, _ high: String?) -> String {
        switch (low, high) {
        case (nil, nil): return first()
        case (nil, .some(let high)): return prependBefore(toDigits(high))
        case (.some(let low), nil): return appendAfter(toDigits(low))
        case (.some(let low), .some(let high)): return midpoint(toDigits(low), toDigits(high))
        }
    }

    /// Whether inserting between `low` and `high` would need to grow
    /// position strings past `maxPrecision` digits — a signal to
    /// rebalance the surrounding list rather than insert again.
    static func needsRebalance(_ low: String, _ high: String) -> Bool {
        let lowDigits = toDigits(low)
        let highDigits = toDigits(high)
        let len = max(max(lowDigits.count, highDigits.count), 1)
        return checkRoom(padInt(lowDigits, len), padInt(highDigits, len), len)
    }

    /// `count` distinct, ascending, evenly spaced positions.
    static func spaced(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        let precision = spacedPrecision(count)
        let denom = ipow(base, precision)
        return (1...count).map { rank in
            let value = (rank * denom) / (count + 1)
            return encode(value, precision)
        }
    }

    // MARK: - internals

    private static func spacedPrecision(_ count: Int) -> Int {
        var p = 1
        while ipow(base, p) <= count { p += 1 }
        return p
    }

    private static func checkRoom(_ lowInt: Int, _ highInt: Int, _ len: Int) -> Bool {
        if highInt - lowInt >= 2 { return false }
        if len >= maxPrecision { return true }
        return checkRoom(lowInt * base, highInt * base, len + 1)
    }

    // Appends after `digits` (no upper bound) by incrementing the last
    // digit when there's room, extending with a fresh "1" digit
    // otherwise — amortized O(log_base(n)) growth for a run of
    // sequential appends, matching the server's identical fix (see
    // `Position.ex`'s `append_after/1` doc comment for why "1" and not
    // "0" or the middle digit).
    private static func appendAfter(_ digits: [Int]) -> String {
        guard let last = digits.last, last < base - 1 else {
            return digitsToString(digits + [1])
        }
        var copy = digits
        copy[copy.count - 1] = last + 1
        return digitsToString(copy)
    }

    private static func prependBefore(_ digits: [Int]) -> String {
        if let decremented = decrement(digits) {
            return digitsToString(decremented)
        }
        // `digits` was already the all-zero minimum — unreachable via
        // any position this module itself ever generates. Kept as a
        // non-crashing fallback, mirroring the server's own guard.
        return digitsToString(digits + [0])
    }

    private static func decrement(_ digits: [Int]) -> [Int]? {
        var reversed = Array(digits.reversed())
        guard doDecrement(&reversed, 0) else { return nil }
        return reversed.reversed()
    }

    private static func doDecrement(_ digits: inout [Int], _ index: Int) -> Bool {
        guard index < digits.count else { return false }
        if digits[index] > 0 {
            digits[index] -= 1
            return true
        }
        guard doDecrement(&digits, index + 1) else { return false }
        digits[index] = base - 1
        return true
    }

    private static func midpoint(_ lowDigits: [Int], _ highDigits: [Int]) -> String {
        let len = max(max(lowDigits.count, highDigits.count), 1)
        var lowInt = padInt(lowDigits, len)
        var highInt = padInt(highDigits, len)
        var currentLen = len
        while highInt - lowInt < 2 {
            lowInt *= base
            highInt *= base
            currentLen += 1
        }
        return encode((lowInt + highInt) / 2, currentLen)
    }

    private static func padInt(_ digits: [Int], _ len: Int) -> Int {
        var padded = digits
        while padded.count < len { padded.append(0) }
        return padded.reduce(0) { $0 * base + $1 }
    }

    private static func encode(_ int: Int, _ len: Int) -> String {
        digitsToString(stripTrailingZeros(intToDigits(int, len)))
    }

    private static func intToDigits(_ int: Int, _ len: Int) -> [Int] {
        var n = int
        var digits: [Int] = []
        for _ in 0..<len {
            digits.insert(n % base, at: 0)
            n /= base
        }
        return digits
    }

    private static func stripTrailingZeros(_ digits: [Int]) -> [Int] {
        var result = digits
        while result.count > 1, result.last == 0 { result.removeLast() }
        if result.isEmpty { result = [0] }
        return result
    }

    private static func toDigits(_ string: String) -> [Int] {
        string.compactMap { charToIndex[$0] }
    }

    private static func digitsToString(_ digits: [Int]) -> String {
        String(digits.map { alphabet[$0] })
    }

    private static func ipow(_ base: Int, _ exponent: Int) -> Int {
        var result = 1
        for _ in 0..<exponent { result *= base }
        return result
    }
}
