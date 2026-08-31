import XCTest
@testable import Playstead

/// Golden-fixture decode tests for `SnapshotResponse`/`CatalogueEntry`
/// against the real server response shape
/// (`PlaysteadWeb.Api.V1.SnapshotController.show/2` +
/// `Playstead.Catalogue.Payload.build/1`, both read in full for this
/// plan). Strict decode contract: an unknown field is ignored, a
/// missing required field is a decode error, never a silent default.
final class SnapshotDecodeTests: XCTestCase {
    /// A golden fixture shaped exactly like a real `/api/v1/snapshot`
    /// response's `catalogue` array entry, including fields this client
    /// does not model (`status`, `title_source`, `manifest_version`,
    /// `recognition`, `attention`, `excluded_at`, `updated_at`) to prove
    /// unknown-field tolerance, plus the full snapshot envelope
    /// (`entries`, `cursor`, `has_more`, `next_after_id`, `job`, `curation`).
    private let goldenSnapshotJSON = """
    {
      "entries": [],
      "cursor": "AAAAAAAAAAA",
      "has_more": false,
      "next_after_id": null,
      "job": [],
      "curation": [],
      "catalogue": [
        {
          "id": "01930000-0000-7000-8000-000000000001",
          "system": "gba",
          "status": "active",
          "display_title": "Test Adventure",
          "title_source": "dat_match",
          "tags": {"region": "us"},
          "manifest_version": 1,
          "members": [
            {
              "ordinal": 0,
              "role": "rom",
              "required": true,
              "sha256": "443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c",
              "size": 4194304,
              "name": "test-adventure.gba"
            }
          ],
          "recognition": {
            "status": "matched",
            "confidence": "exact",
            "provider": "dat-reference",
            "provider_version": "1",
            "reference_name": "Test Adventure (USA)"
          },
          "attention": false,
          "excluded_at": null,
          "updated_at": "2026-08-30T00:00:00Z"
        }
      ]
    }
    """

    func testFullDecodeSucceedsAndToleratesUnknownFields() throws {
        let data = Data(goldenSnapshotJSON.utf8)
        let response = try JSONDecoder().decode(SnapshotResponse.self, from: data)

        XCTAssertEqual(response.catalogue.count, 1)
        let entry = response.catalogue[0]
        XCTAssertEqual(entry.id, "01930000-0000-7000-8000-000000000001")
        XCTAssertEqual(entry.system, "gba")
        XCTAssertEqual(entry.displayTitle, "Test Adventure")
        XCTAssertEqual(entry.tags["region"], "us")
        XCTAssertEqual(entry.members.count, 1)

        let member = entry.members[0]
        XCTAssertEqual(member.ordinal, 0)
        XCTAssertEqual(member.role, "rom")
        XCTAssertTrue(member.required)
        XCTAssertEqual(member.sha256, "443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c")
        XCTAssertEqual(member.size, 4_194_304)
        XCTAssertEqual(member.name, "test-adventure.gba")

        XCTAssertFalse(response.hasMore)
        XCTAssertEqual(response.cursor, "AAAAAAAAAAA")
    }

    func testMissingRequiredMemberFieldFailsDecode() {
        // `role` is required on AssetMember but omitted here — this MUST
        // fail to decode, never silently default to an empty role.
        let brokenJSON = """
        {
          "entries": [], "cursor": "AAAAAAAAAAA", "has_more": false, "next_after_id": null,
          "job": [], "curation": [],
          "catalogue": [
            {
              "id": "01930000-0000-7000-8000-000000000001",
              "system": "gba",
              "display_title": "Test Adventure",
              "tags": {},
              "members": [
                {
                  "ordinal": 0,
                  "required": true,
                  "sha256": "443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c",
                  "size": 4194304,
                  "name": "test-adventure.gba"
                }
              ]
            }
          ]
        }
        """
        let data = Data(brokenJSON.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SnapshotResponse.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMissingRequiredTopLevelFieldFailsDecode() {
        // `display_title` is required on CatalogueEntry but omitted here.
        let brokenJSON = """
        {
          "entries": [], "cursor": "AAAAAAAAAAA", "has_more": false, "next_after_id": null,
          "job": [], "curation": [],
          "catalogue": [
            {
              "id": "01930000-0000-7000-8000-000000000001",
              "system": "gba",
              "tags": {},
              "members": []
            }
          ]
        }
        """
        let data = Data(brokenJSON.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SnapshotResponse.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
}
