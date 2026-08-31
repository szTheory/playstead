import Foundation
import Security

/// The paired-device credential the Phase 1 pairing ceremony writes into
/// the Keychain (D-07, D-10): a device id and a long-lived opaque bearer
/// token, sent only via the `Authorization: Bearer <token>` header —
/// never a URL, never logged.
struct PairingCredential: Equatable {
    let deviceID: String
    let baseURL: URL
    let token: String
}

enum KeychainError: Error, Equatable {
    case notFound
    case unexpectedFormat
    case osFailure(OSStatus)
}

/// Reads and writes the paired device credential in the macOS Keychain.
///
/// `kSecClassGenericPassword`, service `dev.playstead.mac`, account =
/// device id. The token is the item's password data; `baseURL` and
/// `deviceID` ride in the item's generic attribute as a small JSON
/// envelope so a single Keychain item is the credential's complete,
/// self-describing source of truth.
///
/// ## Why the service holds at most one item
///
/// This app pairs **one device per install**: `PairingCredential` names a
/// single `deviceID`, `APIClient` holds a single credential, and there is
/// no surface anywhere that selects between paired identities. The read
/// side reflects that — `loadCredential()` takes no argument, because at
/// the moment it runs the app does not yet know its own device id (the id
/// is *in* the item it is about to read). So a read cannot be scoped by
/// account without storing the account somewhere outside the Keychain,
/// which would defeat the point of the self-describing envelope.
///
/// The invariant is therefore enforced on the **write** side: after
/// storing, `storeCredential` prunes every other account on this service,
/// so a subsequent read has exactly one item to find. Each pairing mints
/// a fresh `device_id` (a fresh account), and before this the service
/// accumulated one item per pairing while `loadCredential` queried on
/// service alone with `kSecMatchLimitOne` — returning an arbitrary, in
/// practice stale, credential. That was observed for real while building
/// `scripts/pair-dev.sh`.
///
/// Belt and braces, the read is deterministic even if the invariant is
/// ever violated from outside this type (the dev pairing script writes
/// items with `security(1)`, not through this code): `loadCredential`
/// enumerates *every* item on the service, orders them most-recently-
/// modified first, and then fetches the chosen item's token with an
/// account-scoped query. So the credential the app authenticates with is
/// always the newest pairing and always names one specific item — never
/// whichever one an unordered single-match query happened to hand back.
struct KeychainStore {
    private let service: String
    private let keychain: SecKeychain?

    /// Production callers omit both arguments and retain the existing
    /// login-Keychain behavior. Hosted tests supply a unique service and a
    /// run-owned file Keychain so no query can escape into the runner's
    /// default search list.
    init(service: String = "dev.playstead.mac", keychain: SecKeychain? = nil) {
        self.service = service
        self.keychain = keychain
    }

    /// Adds the Security.framework search scope used by copy, update, and
    /// delete operations. Kept pure so the exact dictionary boundary is
    /// testable without opening a real Keychain.
    static func scopedMatchQuery(
        _ query: [String: Any],
        searchList: [AnyObject]?
    ) -> [String: Any] {
        guard let searchList else { return query }
        var scoped = query
        scoped[kSecMatchSearchList as String] = searchList
        return scoped
    }

    /// Adds the destination used only by `SecItemAdd`. Search and add use
    /// different Security.framework keys by design; mixing them can fall
    /// back to the user's default Keychain.
    static func scopedAddQuery(
        _ query: [String: Any],
        destination: AnyObject?
    ) -> [String: Any] {
        guard let destination else { return query }
        var scoped = query
        scoped[kSecUseKeychain as String] = destination
        return scoped
    }

    private func matchQuery(_ query: [String: Any]) -> [String: Any] {
        Self.scopedMatchQuery(query, searchList: keychain.map { [$0 as AnyObject] })
    }

    private func addQuery(_ query: [String: Any]) -> [String: Any] {
        Self.scopedAddQuery(query, destination: keychain.map { $0 as AnyObject })
    }

    func loadCredential() -> PairingCredential? {
        // Two steps, because macOS will not return password *data* for a
        // `kSecMatchLimitAll` query — it answers attributes only. So:
        // enumerate every item's attributes to decide which one to use,
        // then fetch that one item's token with an account-scoped query.
        // The account-scoped second step is also what makes the read
        // deterministic: it names exactly one item.
        let listQuery = matchQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ])

        var item: CFTypeRef?
        guard SecItemCopyMatching(listQuery as CFDictionary, &item) == errSecSuccess else {
            return nil
        }

        // `kSecMatchLimitAll` yields an array; tolerate a lone dictionary
        // rather than assuming a shape the Security framework does not
        // actually promise.
        let results: [[String: Any]]
        if let array = item as? [[String: Any]] {
            results = array
        } else if let single = item as? [String: Any] {
            results = [single]
        } else {
            return nil
        }

        // Newest first, so a stale item is only ever reached if the newest
        // one turns out to be unreadable.
        for candidate in Self.orderedCandidates(in: results) {
            guard let token = token(forAccount: candidate.account) else { continue }
            return PairingCredential(
                deviceID: candidate.account, baseURL: candidate.baseURL, token: token
            )
        }
        return nil
    }

    /// One well-formed item found on the service, with everything needed
    /// to order it and to go back for its token.
    struct CredentialLocator: Equatable {
        let account: String
        let baseURL: URL
        let modified: Date
    }

    /// Orders every well-formed item found on the service, most recently
    /// modified first, with the account (device id) as a stable tiebreak
    /// so the result never depends on the order the Security framework
    /// happened to return items in. Items whose envelope does not decode
    /// are dropped rather than allowed to shadow a usable credential.
    ///
    /// Pure over `SecItemCopyMatching`'s own attribute dictionaries, so
    /// the selection rule — the substance of the fix — is directly
    /// testable without a live Keychain.
    static func orderedCandidates(in results: [[String: Any]]) -> [CredentialLocator] {
        results.compactMap { result -> CredentialLocator? in
            guard
                let account = result[kSecAttrAccount as String] as? String,
                let generic = result[kSecAttrGeneric as String] as? Data,
                let envelope = try? JSONDecoder().decode(CredentialEnvelope.self, from: generic)
            else {
                return nil
            }
            return CredentialLocator(
                account: account,
                baseURL: envelope.baseURL,
                modified: result[kSecAttrModificationDate as String] as? Date ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            return lhs.account > rhs.account
        }
    }

    /// The token stored against exactly one account on this service.
    private func token(forAccount account: String) -> String? {
        let query = matchQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func storeCredential(_ credential: PairingCredential) -> Result<Void, KeychainError> {
        let envelope = CredentialEnvelope(baseURL: credential.baseURL)
        guard let genericData = try? JSONEncoder().encode(envelope) else {
            return .failure(.unexpectedFormat)
        }

        let matchQuery = matchQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.deviceID
        ])
        let updateAttributes: [String: Any] = [
            kSecAttrGeneric as String: genericData,
            kSecValueData as String: Data(credential.token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Prefer an in-place update over delete-then-add: if the process
        // is killed between two independent Keychain operations (or
        // SecItemAdd fails, e.g. errSecDuplicateItem/errSecInDarkWake),
        // delete-then-add can leave a window with zero stored credential
        // — the app becomes unexpectedly unpaired rather than keeping
        // either the old or the new one (P1-WR-001).
        //
        // Pruning the *other* accounts happens strictly after the new
        // credential is durable, for the same reason and in the same
        // direction: any crash window leaves a superset of credentials,
        // never none — and `loadCredential`'s newest-wins rule reads
        // correctly through exactly that window.
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return pruneAccounts(otherThan: credential.deviceID)
        }
        guard updateStatus == errSecItemNotFound else {
            return .failure(.osFailure(updateStatus))
        }

        let addQuery = addQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.deviceID,
            kSecAttrGeneric as String: genericData,
            kSecValueData as String: Data(credential.token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ])

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            return .failure(.osFailure(addStatus))
        }
        return pruneAccounts(otherThan: credential.deviceID)
    }

    /// Removes the scoped credential set. This is used by the hosted
    /// two-cycle canary and is also a safe explicit unpair primitive: a
    /// scoped store cannot delete items from any other Keychain.
    @discardableResult
    func deleteCredential() -> Result<Void, KeychainError> {
        let query = matchQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ])
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.osFailure(status))
        }
        return .success(())
    }

    /// Deletes every item on this service whose account is not
    /// `deviceID`, so the one-credential-per-service invariant holds
    /// after any successful write. Returns the first genuine OS failure;
    /// `errSecItemNotFound` means there was nothing to prune, which is
    /// the normal case.
    private func pruneAccounts(otherThan deviceID: String) -> Result<Void, KeychainError> {
        for account in accounts() where account != deviceID {
            let deleteQuery = matchQuery([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ])
            let status = SecItemDelete(deleteQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                return .failure(.osFailure(status))
            }
        }
        return .success(())
    }

    /// Every account currently stored on this service.
    private func accounts() -> [String] {
        let query = matchQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ])
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return [] }
        if let array = item as? [[String: Any]] {
            return array.compactMap { $0[kSecAttrAccount as String] as? String }
        }
        if let single = item as? [String: Any] {
            return [single[kSecAttrAccount as String] as? String].compactMap { $0 }
        }
        return []
    }

    private struct CredentialEnvelope: Codable {
        let baseURL: URL
    }
}
