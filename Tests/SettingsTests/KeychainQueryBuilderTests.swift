import Foundation
import Security
import XCTest
@testable import AllInGentleKit

/// Pins the exact SecItem query dictionaries built by the internal query
/// builders extracted from `KeychainStore` (R-2.1-R-2.4).
///
/// Hermetic by construction: the builders are pure functions, and this suite
/// never instantiates `KeychainStore` against the live keychain.
final class KeychainQueryBuilderTests: XCTestCase {
    func testSaveQueryBuildsExactAddDict() {
        let rows: [(name: String, key: String, value: Data, expected: [(key: String, value: Any)])] = [
            (
                name: "api key",
                key: "all-in-gentle.provider.deepseek.api-key",
                value: Data("sk-test-123".utf8),
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "all-in-gentle.provider.deepseek.api-key"),
                    (kSecValueData as String, Data("sk-test-123".utf8)),
                    (kSecAttrAccessible as String, kSecAttrAccessibleWhenUnlocked),
                ]
            ),
            (
                name: "legacy key",
                key: "legacy.deepseek.key",
                value: Data("another-secret".utf8),
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "legacy.deepseek.key"),
                    (kSecValueData as String, Data("another-secret".utf8)),
                    (kSecAttrAccessible as String, kSecAttrAccessibleWhenUnlocked),
                ]
            ),
        ]

        for row in rows {
            assertQuery(
                { saveQuery(key: row.key, value: row.value) },
                equals: row.expected,
                label: "saveQuery(\(row.name))"
            )
        }
    }

    func testLoadQueryBuildsExactLookupDict() {
        let rows: [(name: String, key: String, expected: [(key: String, value: Any)])] = [
            (
                name: "api key",
                key: "all-in-gentle.provider.deepseek.api-key",
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "all-in-gentle.provider.deepseek.api-key"),
                    (kSecReturnData as String, true),
                    (kSecMatchLimit as String, kSecMatchLimitOne),
                ]
            ),
            (
                name: "custom provider key",
                key: "all-in-gentle.provider.custom.api-key",
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "all-in-gentle.provider.custom.api-key"),
                    (kSecReturnData as String, true),
                    (kSecMatchLimit as String, kSecMatchLimitOne),
                ]
            ),
        ]

        for row in rows {
            assertQuery(
                { loadQuery(key: row.key) },
                equals: row.expected,
                label: "loadQuery(\(row.name))"
            )
        }
    }

    func testDeleteQueryBuildsMinimalTwoKeyDict() {
        let rows: [(name: String, key: String, expected: [(key: String, value: Any)])] = [
            (
                name: "api key",
                key: "all-in-gentle.provider.deepseek.api-key",
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "all-in-gentle.provider.deepseek.api-key"),
                ]
            ),
            (
                name: "custom provider key",
                key: "all-in-gentle.provider.custom.api-key",
                expected: [
                    (kSecClass as String, kSecClassGenericPassword),
                    (kSecAttrAccount as String, "all-in-gentle.provider.custom.api-key"),
                ]
            ),
        ]

        for row in rows {
            assertQuery(
                { deleteQuery(key: row.key) },
                equals: row.expected,
                label: "deleteQuery(\(row.name))"
            )
        }
    }

    /// Asserts `build()` returns exactly the expected key/value pairs, with
    /// Data compared by bytes (via NSData bridging) and exact key count.
    private func assertQuery(
        _ build: () -> [String: Any],
        equals expected: [(key: String, value: Any)],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let query = build()
        XCTAssertEqual(
            query.count, expected.count,
            "\(label): expected \(expected.count) keys, got \(query.count)",
            file: file, line: line
        )
        for (key, value) in expected {
            guard let actual = query[key] else {
                XCTFail("\(label): missing key \(key)", file: file, line: line)
                continue
            }
            switch (actual, value) {
            case (let actualData as Data, let expectedData as Data):
                XCTAssertEqual(
                    actualData as NSData, expectedData as NSData,
                    "\(label): \(key) mismatch", file: file, line: line
                )
            case (let actualString as String, let expectedString as String):
                XCTAssertEqual(
                    actualString, expectedString,
                    "\(label): \(key) mismatch", file: file, line: line
                )
            case (let actualBool as Bool, let expectedBool as Bool):
                XCTAssertEqual(
                    actualBool, expectedBool,
                    "\(label): \(key) mismatch", file: file, line: line
                )
            default:
                XCTFail(
                    "\(label): \(key) has unexpected type \(type(of: actual)) vs \(type(of: value))",
                    file: file, line: line
                )
            }
        }
    }
}
