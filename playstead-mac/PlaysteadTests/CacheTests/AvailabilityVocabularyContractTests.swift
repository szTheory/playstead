import XCTest
@testable import Playstead

/// Plan 03-14 (LIBR-02 gap closure, Task 1): proves
/// `shared/availability-vocabulary.json` and the shipped
/// `AvailabilityVocabulary` Swift constants cannot drift apart --
/// exhaustively, in both directions -- mirroring
/// `SaveCopyContractTests`'s exact pattern for
/// `shared/save-vocabulary.json`. The Elixir side asserts the identical
/// fixture independently (`availability_vocabulary_contract_test.exs`,
/// created by 03-13) -- neither side asserts against the other's stub,
/// which is deliberate: a test whose transport is a stub of its
/// counterpart can go green while the real contract is broken.
final class AvailabilityVocabularyContractTests: XCTestCase {
    private func loadJSONVocabulary(file: StaticString = #filePath) throws -> [String: String] {
        // playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift
        // -> CacheTests -> PlaysteadTests -> playstead-mac -> repo root
        var url = URL(fileURLWithPath: "\(file)")
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.appendPathComponent("shared/availability-vocabulary.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: - Exhaustive equality (the core anti-drift assertion)

    func testJSONVocabularyExactlyMatchesShippedSwiftConstants() throws {
        let json = try loadJSONVocabulary()
        XCTAssertFalse(json.isEmpty, "the JSON vocabulary must not be empty")
        // Equal in BOTH directions at once: a key present in one and
        // absent from the other, or a shared key with a differing
        // value, all fail this single assertion -- "exhaustive," not
        // merely overlapping.
        XCTAssertEqual(json, AvailabilityVocabulary.all)
    }

    func testJSONDeclaresExactlySixValuesOneLabelAndOneAccessibleNameEach() throws {
        let json = try loadJSONVocabulary()
        XCTAssertEqual(json.count, 12)

        let jsonValues = Set(json.keys.compactMap { key -> String? in
            let parts = key.split(separator: ".")
            return parts.count > 1 ? String(parts[1]) : nil
        })
        XCTAssertEqual(jsonValues, Set(AvailabilityVocabulary.values))
    }

    // MARK: - Negative case: both drift directions are actually caught

    func testKeyRemovedFromVocabularyButStillEmittedWouldBeCaught() throws {
        var json = try loadJSONVocabulary()
        json.removeValue(forKey: "filter.ready_offline.label")
        XCTAssertNotEqual(json, AvailabilityVocabulary.all, "removing a JSON key must break exact equality")
    }

    func testVocabularyKeyNeverEmittedWouldBeCaught() throws {
        var json = try loadJSONVocabulary()
        json["filter.phantom_value.label"] = "Phantom"
        XCTAssertNotEqual(json, AvailabilityVocabulary.all, "an extra JSON key must break exact equality")
    }

    func testNoDriftWhenSetsMatch() throws {
        let json = try loadJSONVocabulary()
        XCTAssertEqual(json, AvailabilityVocabulary.all)
    }

    // MARK: - Every declared vocabulary key is used by the shipped Swift surface

    func testEveryVocabularyKeyNamesARealCompiledSwiftConstant() throws {
        let json = try loadJSONVocabulary()
        for (key, value) in json {
            XCTAssertEqual(AvailabilityVocabulary.all[key], value, "key \(key) must name a real compiled Swift constant")
        }
    }

    // MARK: - The six values are frozen and in the UI-SPEC's order

    func testSixFrozenValuesInDisplayOrder() {
        XCTAssertEqual(AvailabilityVocabulary.values, [
            "needs_attention", "missing_dependency", "downloading", "ready_offline", "queued", "server_only",
        ])
    }

    func testLabelAndAccessibleNameReturnNilForAnUnknownValue() {
        XCTAssertNil(AvailabilityVocabulary.label("not_a_real_value"))
        XCTAssertNil(AvailabilityVocabulary.accessibleName("not_a_real_value"))
    }
}
