import Foundation
import Security

/// Secure API key storage backed by the macOS Keychain
enum Keychain {
    private static let service = "com.zikai.voxkit"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        if let value = read(service: service, account: account) { return value }
        // Migrate forward from the pre-rename (VoxNote) service on first read
        if let legacy = read(service: "com.zikai.voxnote", account: account) {
            set(legacy, account: account)
            return legacy
        }
        return nil
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    static func has(account: String) -> Bool {
        !(get(account: account) ?? "").isEmpty
    }
}
