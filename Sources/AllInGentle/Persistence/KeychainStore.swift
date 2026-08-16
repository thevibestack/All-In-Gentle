import Foundation
import Security

/// Abstract interface for Keychain storage so production code and tests can
/// swap implementations without changing call sites.
public protocol KeychainStoring: Actor {
    func save(key: String, value: String) throws
    func load(key: String) throws -> String?
    func delete(key: String) throws
}

/// Builds the SecItem query used by `KeychainStore.save(key:value:)`.
///
/// Internal pure function so tests can pin the exact query without touching
/// the live keychain (R-G4).
func saveQuery(key: String, value: Data) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecValueData as String: value,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ]
}

/// Builds the SecItem query used by `KeychainStore.load(key:)`.
func loadQuery(key: String) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
}

/// Builds the SecItem query used by `KeychainStore.delete(key:)`.
func deleteQuery(key: String) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
    ]
}

/// Keychain-backed credential store with an atomic upsert.
///
/// `save` updates an existing item and only falls back to adding a new one
/// when the item is absent, so there is never a delete-then-add window that
/// could lose a credential. `load` returns `nil` ONLY for a missing item and
/// throws for every other failure, so callers can distinguish "no key yet"
/// from "keychain broken".
public actor KeychainStore: KeychainStoring {
    private let service: String?
    private let secItem: any SecItemOperating

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - service: Optional `kSecAttrService` scoping. Production callers
    ///     leave it `nil` (matching legacy behavior); tests pass a dedicated
    ///     service so tearDown can remove only test items.
    ///   - secItem: The Security framework seam, injectable for tests.
    public init(
        service: String? = nil,
        secItem: any SecItemOperating = SecItemSystem()
    ) {
        self.service = service
        self.secItem = secItem
    }

    public func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AllInGentleError.invalidConfiguration("Unable to encode keychain value")
        }

        var query = saveQuery(key: key, value: data)
        if let service {
            query[kSecAttrService as String] = service
        }

        let updateStatus = secItem.update(
            query,
            attributesToUpdate: [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = secItem.add(addQuery)
            guard addStatus == errSecSuccess else {
                throw AllInGentleError.invalidConfiguration("Keychain save failed: \(addStatus)")
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw AllInGentleError.invalidConfiguration("Keychain save failed: \(updateStatus)")
        }
    }

    public func load(key: String) throws -> String? {
        var query = loadQuery(key: key)
        if let service {
            query[kSecAttrService as String] = service
        }

        var result: AnyObject?
        let status = secItem.copyMatching(query, result: &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw AllInGentleError.persistenceFailure("Keychain load failed: \(status)")
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(key: String) throws {
        var query = deleteQuery(key: key)
        if let service {
            query[kSecAttrService as String] = service
        }
        let status = secItem.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AllInGentleError.persistenceFailure("Keychain delete failed: \(status)")
        }
    }
}
