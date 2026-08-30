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

/// Reads (and, for the pairing ceremony this phase does not yet ship,
/// would write) the paired device credential from the macOS Keychain.
///
/// `kSecClassGenericPassword`, service `dev.playstead.mac`, account =
/// device id. The token is the item's password data; `baseURL` and
/// `deviceID` ride in the item's generic attribute as a small JSON
/// envelope so a single Keychain item is the credential's complete,
/// self-describing source of truth.
struct KeychainStore {
    private let service = "dev.playstead.mac"

    func loadCredential() -> PairingCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let result = item as? [String: Any] else {
            return nil
        }

        guard
            let tokenData = result[kSecValueData as String] as? Data,
            let token = String(data: tokenData, encoding: .utf8),
            let account = result[kSecAttrAccount as String] as? String,
            let generic = result[kSecAttrGeneric as String] as? Data,
            let envelope = try? JSONDecoder().decode(CredentialEnvelope.self, from: generic)
        else {
            return nil
        }

        return PairingCredential(deviceID: account, baseURL: envelope.baseURL, token: token)
    }

    @discardableResult
    func storeCredential(_ credential: PairingCredential) -> Result<Void, KeychainError> {
        let envelope = CredentialEnvelope(baseURL: credential.baseURL)
        guard let genericData = try? JSONEncoder().encode(envelope) else {
            return .failure(.unexpectedFormat)
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.deviceID
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.deviceID,
            kSecAttrGeneric as String: genericData,
            kSecValueData as String: Data(credential.token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            return .failure(.osFailure(status))
        }
        return .success(())
    }

    private struct CredentialEnvelope: Codable {
        let baseURL: URL
    }
}
