import XCTest
import Security
@testable import Playstead

/// Covers the account-scoping defect in `KeychainStore`: `loadCredential()`
/// queried on service alone with `kSecMatchLimitOne` and no account
/// predicate, so once a second pairing had written a second item (each
/// pairing mints a fresh `device_id`, i.e. a fresh account) the read
/// returned an arbitrary — in practice stale — credential. It was
/// reproduced for real while building `scripts/pair-dev.sh`.
///
/// ## What is and isn't covered here, honestly
///
/// These tests exercise `orderedCandidates(in:)` — the pure selection rule
/// that decides *which* item on the service `loadCredential` goes back for
/// — over exactly the attribute dictionaries `SecItemCopyMatching` returns
/// for a `kSecMatchLimitAll` query. That rule is the substance of the
/// read-side fix, and every ordering case is asserted here.
///
/// A full `storeCredential` → `loadCredential` round trip against the
/// **real** Security framework is deliberately NOT tested, and the gap is
/// stated rather than papered over. It was attempted and removed: reading
/// an item's password data out of the legacy macOS file keychain (which is
/// the keychain this app uses, because `scripts/pair-dev.sh` writes into it
/// with `security(1)`) can raise a per-item ACL dialog, and under
/// `xcodebuild test` nothing dismisses that dialog — the run hangs
/// indefinitely rather than failing. The same environment is already known
/// to refuse Keychain access outright with `errSecInDarkWake` (see plan
/// 03-03's SUMMARY and `APIClient.credentialOverride`, which exists for
/// exactly that reason). Making it testable would mean moving to the
/// data-protection keychain (`kSecUseDataProtectionKeychain`), which would
/// change where the credential actually lives and break the dev pairing
/// script — a real behavior change to suit a test, not a fix.
///
/// So the write-side invariant (`storeCredential` prunes every other
/// account, leaving at most one item on the service) is covered by code
/// review and by manual verification with `scripts/pair-dev.sh`, not by an
/// automated test. Nothing here asserts it.
final class KeychainScopingTests: XCTestCase {
    private let baseURL = URL(string: "https://sync.test")!

    /// The attribute dictionary shape `SecItemCopyMatching` returns for a
    /// `kSecMatchLimitAll` query: attributes only, never password data
    /// (macOS declines to return data for a multi-item query, which is
    /// why `loadCredential`'s read is two steps).
    private func attributeDictionary(
        account: String,
        modified: Date?,
        baseURL: URL? = nil,
        envelopeOverride: Data? = nil
    ) -> [String: Any] {
        let envelope = envelopeOverride
            ?? (try! JSONEncoder().encode(["baseURL": (baseURL ?? self.baseURL).absoluteString]))
        var dict: [String: Any] = [
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: envelope
        ]
        if let modified {
            dict[kSecAttrModificationDate as String] = modified
        }
        return dict
    }

    /// The defect, directly: two pairings on one service. The newer one
    /// must win, in either input order.
    func testOrderedCandidatesPutsTheMostRecentlyModifiedItemFirst() {
        let old = attributeDictionary(account: "device-old", modified: Date(timeIntervalSince1970: 1_000))
        let new = attributeDictionary(account: "device-new", modified: Date(timeIntervalSince1970: 2_000))

        for results in [[old, new], [new, old]] {
            XCTAssertEqual(
                KeychainStore.orderedCandidates(in: results).map(\.account),
                ["device-new", "device-old"],
                "a fresh pairing must outrank the stale item it landed beside"
            )
        }
    }

    func testOrderedCandidatesIsDeterministicWhenModificationDatesTie() {
        let stamp = Date(timeIntervalSince1970: 1_000)
        let a = attributeDictionary(account: "device-a", modified: stamp)
        let b = attributeDictionary(account: "device-b", modified: stamp)

        XCTAssertEqual(KeychainStore.orderedCandidates(in: [a, b]).map(\.account), ["device-b", "device-a"])
        XCTAssertEqual(
            KeychainStore.orderedCandidates(in: [b, a]).map(\.account), ["device-b", "device-a"],
            "the tiebreak must not depend on the order the Security framework happens to return items in"
        )
    }

    func testOrderedCandidatesDropsItemsWithAnUndecodableEnvelope() {
        let malformed = attributeDictionary(
            account: "device-broken",
            modified: Date(timeIntervalSince1970: 9_000),
            envelopeOverride: Data("not json".utf8)
        )
        let good = attributeDictionary(account: "device-good", modified: Date(timeIntervalSince1970: 1_000))

        // The malformed item is *newer*; a rule that ordered first and
        // decoded second would strand the app on an unreadable item.
        XCTAssertEqual(KeychainStore.orderedCandidates(in: [malformed, good]).map(\.account), ["device-good"])
    }

    func testOrderedCandidatesDropsItemsWithNoEnvelopeAtAll() {
        let noGeneric: [String: Any] = [kSecAttrAccount as String: "device-bare"]
        XCTAssertTrue(KeychainStore.orderedCandidates(in: [noGeneric]).isEmpty)
    }

    func testOrderedCandidatesRanksAnItemWithoutAModificationDateLast() {
        let undated = attributeDictionary(account: "device-undated", modified: nil)
        let dated = attributeDictionary(account: "device-dated", modified: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(
            KeychainStore.orderedCandidates(in: [undated, dated]).map(\.account),
            ["device-dated", "device-undated"]
        )
    }

    /// The base URL every request path is resolved against comes from the
    /// chosen item's own envelope — so picking the wrong item points the
    /// client at the wrong server, not merely at the wrong token.
    func testOrderedCandidatesCarriesTheEnvelopesBaseURL() {
        let stale = attributeDictionary(
            account: "device-old",
            modified: Date(timeIntervalSince1970: 1),
            baseURL: URL(string: "https://stale.test")!
        )
        let fresh = attributeDictionary(
            account: "device-new",
            modified: Date(timeIntervalSince1970: 2),
            baseURL: URL(string: "https://fresh.test")!
        )

        XCTAssertEqual(
            KeychainStore.orderedCandidates(in: [stale, fresh]).first?.baseURL,
            URL(string: "https://fresh.test")!
        )
    }

    func testOrderedCandidatesOfNothingIsEmpty() {
        XCTAssertTrue(KeychainStore.orderedCandidates(in: []).isEmpty)
    }
}
