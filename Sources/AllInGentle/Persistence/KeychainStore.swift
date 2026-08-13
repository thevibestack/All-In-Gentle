import Foundation
import Security

/// Abstract interface for Keychain storage so production code and tests can
/// swap implementations without changing call sites.
public protocol KeychainStoring: Actor {
    func save(key: String, value: String) throws
    func load(key: String) -> String?
    func delete(key: String)
}

public actor KeychainStore: KeychainStoring {
    public init() {}

    public func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AllInGentleError.invalidConfiguration("Unable to encode keychain value")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AllInGentleError.invalidConfiguration("Keychain save failed: \(status)")
        }
    }

    public func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
