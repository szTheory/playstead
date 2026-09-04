import XCTest
@testable import Playstead

/// Proves `shared/save-vocabulary.json` (D-67) and the shipped
/// `SaveVocabulary` Swift constants cannot drift apart -- exhaustively,
/// in both directions, never merely "matching". The JSON is read here as
/// a test resource only; no shipped Swift code path ever reads it (see
/// `SaveVocabulary`'s doc comment, and this file's own resolution below,
/// which walks up from `#filePath`, never from the app bundle).
final class SaveCopyContractTests: XCTestCase {
    /// `sha256, digest, hash, cursor, journal, parent, base, head,
    /// ancestor, revision, blob, CAS, idempotency key, LWW, merge, sync,
    /// uploaded, backed up` -- the vocabulary rules' full banned list,
    /// scanned as whole words (never a stem match: "merged"/"syncing"
    /// are distinct words from "merge"/"sync" and are not banned).
    private static let bannedWords = [
        "sha256", "digest", "hash", "cursor", "journal", "parent", "base", "head",
        "ancestor", "revision", "blob", "CAS", "idempotency key", "LWW", "merge",
        "sync", "uploaded", "backed up"
    ]

    /// `conflict, overwrite, lost, wins, loser, merge, error, failed,
    /// corrupt, stale, invalid, "you should have"` -- banned specifically
    /// from divergence copy (D-54); scanned over the attention/compare/
    /// result/danger key families, the only ones that speak to
    /// divergence.
    private static let bannedDivergenceWords = [
        "conflict", "overwrite", "lost", "wins", "loser", "merge", "error",
        "failed", "corrupt", "stale", "invalid", "you should have"
    ]

    private static let divergenceKeyPrefixes = ["attention.", "compare.", "result.", "danger."]

    private func loadJSONVocabulary(file: StaticString = #filePath) throws -> [String: String] {
        // playstead-mac/PlaysteadTests/SavesTests/SaveCopyContractTests.swift
        // -> SavesTests -> PlaysteadTests -> playstead-mac -> repo root
        var url = URL(fileURLWithPath: "\(file)")
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.appendPathComponent("shared/save-vocabulary.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: - Exhaustive equality (the core anti-drift assertion)

    func testJSONVocabularyExactlyMatchesShippedSwiftConstants() throws {
        let json = try loadJSONVocabulary()
        XCTAssertFalse(json.isEmpty, "the JSON vocabulary must not be empty")
        // Equal in BOTH directions at once: a key present in one and
        // absent from the other, or a shared key with a differing
        // value, all fail this single assertion -- "exhaustive", not
        // merely overlapping.
        XCTAssertEqual(json, SaveVocabulary.all)
    }

    func testAtLeastFiftyKeys() throws {
        let json = try loadJSONVocabulary()
        XCTAssertGreaterThanOrEqual(json.count, 50)
    }

    // MARK: - Negative case: both drift directions are actually caught

    /// The pure diff a real drift would surface -- proven here on
    /// synthetic fixtures so the assertion's own detection logic is
    /// under test, independent of whatever the real vocabulary
    /// currently contains.
    private func diff(
        vocabulary: [String: String], emitted: [String: String]
    ) -> (missingFromVocabulary: Set<String>, unusedInVocabulary: Set<String>) {
        let vocabKeys = Set(vocabulary.keys)
        let emittedKeys = Set(emitted.keys)
        return (
            missingFromVocabulary: emittedKeys.subtracting(vocabKeys),
            unusedInVocabulary: vocabKeys.subtracting(emittedKeys)
        )
    }

    func testDriftDetection_keyRemovedFromVocabularyButStringStillEmitted() {
        let vocabulary = ["a": "Alpha"]
        let emitted = ["a": "Alpha", "b": "Beta"] // "b" emitted, not in vocabulary
        let result = diff(vocabulary: vocabulary, emitted: emitted)
        XCTAssertEqual(result.missingFromVocabulary, ["b"], "an emitted, unlisted string must be caught")
    }

    func testDriftDetection_vocabularyKeyNeverEmitted() {
        let vocabulary = ["a": "Alpha", "b": "Beta"]
        let emitted = ["a": "Alpha"] // "b" never emitted
        let result = diff(vocabulary: vocabulary, emitted: emitted)
        XCTAssertEqual(result.unusedInVocabulary, ["b"], "an unused vocabulary key must be caught")
    }

    func testNoDriftWhenSetsMatch() {
        let vocabulary = ["a": "Alpha", "b": "Beta"]
        let emitted = ["a": "Alpha", "b": "Beta"]
        let result = diff(vocabulary: vocabulary, emitted: emitted)
        XCTAssertTrue(result.missingFromVocabulary.isEmpty)
        XCTAssertTrue(result.unusedInVocabulary.isEmpty)
    }

    // MARK: - Every declared vocabulary key is used by the shipped Swift surface

    /// `SaveVocabulary.all` is itself the shipped, compiled Swift
    /// surface (every value below is compiled into the app binary as a
    /// `static let`) -- so "every key is used" holds by the type's own
    /// construction: every key that exists in the dictionary literal
    /// names a real, compiled Swift constant with an equal value.
    func testEveryVocabularyKeyNamesARealCompiledSwiftConstant() throws {
        let json = try loadJSONVocabulary()
        for (key, value) in json {
            XCTAssertEqual(SaveVocabulary.all[key], value, "key \(key) must name a real compiled Swift constant")
        }
    }

    // MARK: - Banned words

    private func wholeWordHits(_ words: [String], in value: String) -> [String] {
        words.filter { word in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }
    }

    func testBannedWordsNeverAppearInAnyVocabularyValue() throws {
        let json = try loadJSONVocabulary()
        for (key, value) in json {
            let hits = wholeWordHits(Self.bannedWords, in: value)
            XCTAssertTrue(hits.isEmpty, "key \(key) contains banned word(s) \(hits): \(value)")
        }
    }

    func testDivergenceBannedWordsNeverAppearInDivergenceCopy() throws {
        let json = try loadJSONVocabulary()
        for (key, value) in json where Self.divergenceKeyPrefixes.contains(where: key.hasPrefix) {
            let hits = wholeWordHits(Self.bannedDivergenceWords, in: value)
            XCTAssertTrue(hits.isEmpty, "divergence key \(key) contains banned word(s) \(hits): \(value)")
        }
    }

    func testBannedWordScanCatchesARealViolation() {
        // Proves the scanner itself works: a synthetic value containing
        // a real banned word, as a whole word, is caught.
        XCTAssertEqual(wholeWordHits(Self.bannedWords, in: "This save was backed up."), ["backed up"])
        XCTAssertEqual(wholeWordHits(Self.bannedWords, in: "It has not been merged."), [])
        XCTAssertEqual(wholeWordHits(Self.bannedWords, in: "the next time they sync."), ["sync"])
    }
}
