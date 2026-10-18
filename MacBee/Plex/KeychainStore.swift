import Foundation
import OSLog
import Security

private let keychainLog = Logger(subsystem: "com.troyhomenchuk.MacBee", category: "Keychain")

/// Stores MacBee's Plex token in the modern (data protection) keychain,
/// which doesn't show the "wants to access key" password prompt.
/// On first read it moves any token saved in the old keychain over automatically.
/// The modern keychain needs the app signed with an Apple team and the Keychain Sharing entitlement;
/// without it (error -34018) MacBee keeps using the old keychain so Plex still works.
enum KeychainStore {
    static let service = "MacBee Plex"
    static let plexTokenAccount = "token"

    // MARK: - Public

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let status = add(value, account: account, modern: true)
        if status == errSecMissingEntitlement {
            // -34018: the app is missing the keychain entitlement (see setup notes); fall back to the old keychain.
            print("KeychainStore: no keychain entitlement (-34018), using the old keychain")
            return add(value, account: account, modern: false) == errSecSuccess
        }
        if status != errSecSuccess {
            print("KeychainStore save failed: \(status)")
        }
        return status == errSecSuccess
    }

    static func read(account: String) -> String? {
        if let value = readItem(account: account, modern: true) {
            return value
        }
        // One-time move from the old keychain (may prompt one last time)
        if let old = readItem(account: account, modern: false) {
            if add(old, account: account, modern: true) == errSecSuccess {
                SecItemDelete(baseQuery(account: account, modern: false) as CFDictionary)
            }
            return old
        }
        return nil
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account, modern: true) as CFDictionary)
        SecItemDelete(baseQuery(account: account, modern: false) as CFDictionary)
    }

    // MARK: - Private

    private static func add(_ value: String, account: String, modern: Bool) -> OSStatus {
        var query = baseQuery(account: account, modern: modern)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(account: String, modern: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if modern {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func readItem(account: String, modern: Bool) -> String? {
        var query = baseQuery(account: account, modern: modern)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        keychainLog.notice("read \(modern ? "modern" : "old", privacy: .public) keychain: \(status, privacy: .public)")
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
