import Foundation
import XCTest
@testable import AllInGentleKit

final class IntegrationTests: XCTestCase {
    private var openCodeDBPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
    }

    private var engramBaseURL: URL {
        URL(string: "http://127.0.0.1:7437")!
    }

    // MARK: - OpenCode SQLite read-only enforcement

    func testOpenCodeClientRejectsMutations() async throws {
        let path = openCodeDBPath
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: path),
            "OpenCode database not found at \(path)"
        )

        let client = OpenCodeClient(dbPath: path)
        do {
            _ = try await client.executeReadOnly("DELETE FROM session WHERE id = 'x'")
            XCTFail("Expected read-only violation for DELETE statement")
        } catch {
            guard case .readOnlyViolation = error as? AllInGentleError else {
                XCTFail("Expected readOnlyViolation, got \(error)")
                return
            }
        }
    }

    func testOpenCodeClientReadsLiveProjects() async throws {
        let path = openCodeDBPath
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: path),
            "OpenCode database not found at \(path)"
        )

        let client = OpenCodeClient(dbPath: path)
        let projects = try await client.projects()
        XCTAssertFalse(projects.isEmpty, "Expected at least one project from the live OpenCode DB")
    }

    func testOpenCodeClientReadsLiveTokenUsage() async throws {
        let path = openCodeDBPath
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: path),
            "OpenCode database not found at \(path)"
        )

        let client = OpenCodeClient(dbPath: path)
        let usage = try await client.tokenUsage(limit: 10)
        XCTAssertGreaterThanOrEqual(usage.count, 0, "Token usage query should complete without error")
    }

    // MARK: - Engram HTTP integration

    func testEngramClientHealthAndSearch() async throws {
        let client = EngramClient(baseURL: engramBaseURL)
        let healthy = try? await client.health()
        try XCTSkipIf(healthy != true, "Engram HTTP server not available at \(engramBaseURL)")

        let results = try await client.search(query: "all-in-gentle", limit: 5)
        XCTAssertGreaterThanOrEqual(results.count, 0, "Engram search should complete without error")
    }
}
