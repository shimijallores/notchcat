import Foundation
import Security

/// Stores one secret (the refresh token) in the macOS Keychain.
struct KeychainStore {
    let service: String
    let account: String

    /// Tests that use a throwaway database must never touch the real login.
    static var defaultService: String {
        ProcessInfo.processInfo.environment["NOTCHCAT_DB"] == nil ? "app.notchcat.sync" : "app.notchcat.sync.test"
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ secret: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData as String] = Data(secret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
