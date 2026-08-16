import Foundation
import Security

/// Abstract interface for Keychain storage so production code and tests can
/// swap implementations without changing call sites.
public protocol KeychainStoring: Actor {
    func save(key: String, value: String) throws
    func load(key: String) throws -> String?
    func delete(key: String) throws
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

        let query = baseQuery(key: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let updateStatus = secItem.update(query, attributesToUpdate: attributes)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            for (attributeKey, attributeValue) in attributes {
                addQuery[attributeKey] = attributeValue
            }
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
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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
        let status = secItem.delete(baseQuery(key: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AllInGentleError.persistenceFailure("Keychain delete failed: \(status)")
        }
    }

    private func baseQuery(key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        if let service {
            query[kSecAttrService as String] = service
        }
        return query
    }
}
