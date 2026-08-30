import Foundation
import Security

/// Probe 6: Keychain access from the notarized/dev-signed, hardened-runtime,
/// non-sandboxed SpikeHost build. Exposes the raw OSStatus so a hardened-runtime
/// keychain denial is distinguishable from a not-found result. This validates the
/// same Keychain path P1 D-07 uses for the pairing credential.
enum KeychainProbe {
    static let service = "dev.playstead.spikehost"

    /// Stores `secret` under `account`, returns the raw OSStatus.
    @discardableResult
    static func store(account: String, secret: String) -> OSStatus {
        let secretData = Data(secret.utf8)

        // Remove any pre-existing item first so repeated probe runs are idempotent.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: secretData
        ]
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Reads the value stored under `account`. Returns (status, value-if-found).
    static func read(account: String) -> (OSStatus, String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return (status, nil)
        }
        return (status, String(data: data, encoding: .utf8))
    }
}
