import Foundation
import AllInGentleKit

/// In-memory `KeychainStoring` double for hermetic tests.
///
/// Supports scripted failures for the migrator's error paths: set
/// `setFailNextSave` or `setFailNextLoad` before a call to make the matching
/// operation throw once.
public actor MockKeychain: KeychainStoring {
    private var storage: [String: String] = [:]
    private var failNextSave = false
    private var failNextLoad = false

    public init() {}

    public func setFailNextSave() {
        failNextSave = true
    }

    public func setFailNextLoad() {
        failNextLoad = true
    }

    public func save(key: String, value: String) throws {
        if failNextSave {
            failNextSave = false
            throw AllInGentleError.persistenceFailure("Mock keychain save failure")
        }
        storage[key] = value
    }

    public func load(key: String) throws -> String? {
        if failNextLoad {
            failNextLoad = false
            throw AllInGentleError.persistenceFailure("Mock keychain load failure")
        }
        return storage[key]
    }

    public func delete(key: String) throws {
        storage[key] = nil
    }
}
