import Foundation
import Security

/// Abstraction over the Security framework's `SecItem` C API so production
/// code and tests can swap implementations without touching the real keychain.
public protocol SecItemOperating: Sendable {
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any], result: inout AnyObject?) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// Default ``SecItemOperating`` that forwards directly to the Security framework.
public struct SecItemSystem: SecItemOperating {
    public init() {}

    public func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }

    public func copyMatching(_ query: [String: Any], result: inout AnyObject?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, &result)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
