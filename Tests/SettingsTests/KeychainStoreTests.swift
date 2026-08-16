import Foundation
import XCTest
import Security
@testable import AllInGentleKit

/// Tests the atomic upsert and throwing surface of ``KeychainStore``.
///
/// Hybrid strategy (design D2): real-keychain happy paths run against a
/// dedicated `kSecAttrService` so tearDown can remove every test item without
/// touching production items (which carry no service), and a ``SecItemOperating``
/// seam drives deterministic failure paths.
@MainActor
final class KeychainStoreTests: XCTestCase {
    private var service: String!

    override func setUp() async throws {
        try await super.setUp()
        service = "all-in-gentle.tests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        if let service {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
        try await super.tearDown()
    }

    private func makeStore() -> KeychainStore {
        KeychainStore(service: service)
    }

    private func makeAccount() -> String {
        "account-\(UUID().uuidString)"
    }

    // MARK: - Real keychain (happy paths)

    func testUpsertCreatesWhenItemMissing() async throws {
        let store = makeStore()
        let account = makeAccount()

        try await store.save(key: account, value: "first")

        let loaded = try await store.load(key: account)
        XCTAssertEqual(loaded, "first")
    }

    func testUpsertOverwritesExistingItem() async throws {
        let store = makeStore()
        let account = makeAccount()

        try await store.save(key: account, value: "first")
        try await store.save(key: account, value: "second")

        let loaded = try await store.load(key: account)
        XCTAssertEqual(loaded, "second")
    }

    func testLoadReturnsNilWhenItemMissing() async throws {
        let store = makeStore()

        let loaded = try await store.load(key: makeAccount())
        XCTAssertNil(loaded)
    }

    func testDeleteRemovesItem() async throws {
        let store = makeStore()
        let account = makeAccount()
        try await store.save(key: account, value: "secret")

        try await store.delete(key: account)

        let loaded = try await store.load(key: account)
        XCTAssertNil(loaded)
    }

    func testDeleteMissingItemIsIgnored() async throws {
        let store = makeStore()

        try await store.delete(key: makeAccount())
    }

    // MARK: - Seam (deterministic failures)

    func testLoadThrowsOnAuthFailure() async throws {
        let store = KeychainStore(secItem: FailingSecItem(status: errSecInteractionNotAllowed))

        do {
            _ = try await store.load(key: makeAccount())
            XCTFail("Expected load to throw")
        } catch let error as AllInGentleError {
            guard case .persistenceFailure = error else {
                XCTFail("Expected persistenceFailure, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AllInGentleError, got \(error)")
        }
    }

    func testSaveThrowsWhenUpdateFails() async throws {
        let store = KeychainStore(secItem: FailingSecItem(status: errSecAuthFailed))

        do {
            try await store.save(key: makeAccount(), value: "value")
            XCTFail("Expected save to throw")
        } catch let error as AllInGentleError {
            guard case .invalidConfiguration = error else {
                XCTFail("Expected invalidConfiguration, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AllInGentleError, got \(error)")
        }
    }

    func testDeleteThrowsOnFailure() async throws {
        let store = KeychainStore(secItem: FailingSecItem(status: errSecAuthFailed))

        do {
            try await store.delete(key: makeAccount())
            XCTFail("Expected delete to throw")
        } catch let error as AllInGentleError {
            guard case .persistenceFailure = error else {
                XCTFail("Expected persistenceFailure, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AllInGentleError, got \(error)")
        }
    }

    // MARK: - Seam (atomic upsert shape)

    func testSaveNeverDeletesBeforeAdding() async throws {
        let recorder = RecordingSecItem()
        let store = KeychainStore(secItem: recorder)

        try await store.save(key: "k", value: "v")

        XCTAssertEqual(recorder.deleteCount, 0, "save must not delete first")
        XCTAssertEqual(recorder.updateCount, 1, "save must update an existing item")
        XCTAssertEqual(recorder.addCount, 1, "save must add after update reports not-found")
    }
}

/// ``SecItemOperating`` stub that always returns a fixed status.
private struct FailingSecItem: SecItemOperating {
    let status: OSStatus

    func add(_ query: [String: Any]) -> OSStatus { status }
    func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus { status }
    func copyMatching(_ query: [String: Any], result: inout AnyObject?) -> OSStatus { status }
    func delete(_ query: [String: Any]) -> OSStatus { status }
}

/// ``SecItemOperating`` recorder that reports not-found from update and counts
/// every call, proving the upsert never opens a delete-then-add window.
private final class RecordingSecItem: SecItemOperating, @unchecked Sendable {
    private(set) var addCount = 0
    private(set) var updateCount = 0
    private(set) var deleteCount = 0

    func add(_ query: [String: Any]) -> OSStatus {
        addCount += 1
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        updateCount += 1
        return errSecItemNotFound
    }

    func copyMatching(_ query: [String: Any], result: inout AnyObject?) -> OSStatus {
        errSecItemNotFound
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCount += 1
        return errSecSuccess
    }
}
