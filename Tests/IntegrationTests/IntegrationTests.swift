import Foundation
import XCTest
@testable import AllInGentleKit

// MARK: - Mock transport

/// Per-instance handler box shared with `MockURLProtocol`.
///
/// `URLSession` instantiates `URLProtocol` subclasses via
/// `init(request:cachedResponse:client:)`, so the handler cannot be injected
/// through an initializer. A single immutable `static let` reference with
/// NSLock-guarded interior mutability avoids the `nonisolated(unsafe) static
/// var` data-race pattern (F22): the box is a constant, not a mutable static.
private final class HandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    func set(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.withLock { self.handler = handler }
    }

    func call(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let handler else { throw URLError(.resourceUnavailable) }
        return try handler(request)
    }
}

private final class MockURLProtocol: URLProtocol {
    static let box = HandlerBox()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.box.call(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class IntegrationTests: XCTestCase {
    private var openCodeDBPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
    }

    private var engramBaseURL: URL {
        URL(string: "http://127.0.0.1:7437")!
    }

    // MARK: - Test helpers

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeEngramClient() -> EngramClient {
        EngramClient(baseURL: engramBaseURL, urlSession: makeMockSession())
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

    // MARK: - Engram hermetic tests

    func testEngramHealthParses200() async throws {
        MockURLProtocol.box.set { request in
            guard let url = request.url else { throw URLError(.badURL) }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(url.path, "/health")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"service":"engram","status":"ok","version":"0.1.0"}"#.utf8)
            return (response, data)
        }

        let healthy = try await makeEngramClient().health()
        XCTAssertTrue(healthy)
    }

    func testEngramHealthThrowsOnUnavailable() async throws {
        MockURLProtocol.box.set { request in
            guard let url = request.url else { throw URLError(.badURL) }
            XCTAssertEqual(url.path, "/health")
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = makeEngramClient()
        do {
            _ = try await client.health()
            XCTFail("Expected sourceUnavailable for non-200 health response")
        } catch {
            guard case AllInGentleError.sourceUnavailable = error else {
                return XCTFail("Expected sourceUnavailable, got \(error)")
            }
        }
    }

    func testEngramSearchParsesObservations() async throws {
        MockURLProtocol.box.set { request in
            guard let url = request.url else { throw URLError(.badURL) }
            XCTAssertEqual(url.path, "/search")
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(queryItems.first(where: { $0.name == "q" })?.value, "all-in-gentle")
            XCTAssertEqual(queryItems.first(where: { $0.name == "limit" })?.value, "5")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            [
              {
                "sync_id": "obs-1",
                "title": "Title A",
                "content": "Body A",
                "project": "gentle-ai",
                "tags": ["decisions", "api"],
                "created_at": "2026-08-15 10:00:00"
              },
              {
                "sync_id": "obs-2",
                "title": "Title B",
                "content": "Body B",
                "project": null,
                "tags": [],
                "updated_at": "2026-08-14 09:30:00"
              }
            ]
            """
            return (response, Data(json.utf8))
        }

        let results = try await makeEngramClient().search(query: "all-in-gentle", limit: 5)

        XCTAssertEqual(results.count, 2)

        XCTAssertEqual(results[0].id, "obs-1")
        XCTAssertEqual(results[0].title, "Title A")
        XCTAssertEqual(results[0].content, "Body A")
        XCTAssertEqual(results[0].project, "gentle-ai")
        XCTAssertEqual(results[0].tags, ["decisions", "api"])

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(results[0].createdAt, formatter.date(from: "2026-08-15 10:00:00"))

        XCTAssertEqual(results[1].id, "obs-2")
        XCTAssertNil(results[1].project)
        XCTAssertEqual(results[1].tags, [])
        XCTAssertEqual(results[1].createdAt, formatter.date(from: "2026-08-14 09:30:00"))
    }

    func testEngramProjectsDedup() async throws {
        MockURLProtocol.box.set { request in
            guard let url = request.url else { throw URLError(.badURL) }
            XCTAssertEqual(url.path, "/search")
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(queryItems.first(where: { $0.name == "q" })?.value, "")
            XCTAssertEqual(queryItems.first(where: { $0.name == "limit" })?.value, "1000")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            [
              {"sync_id": "o1", "title": "T1", "content": "C1", "project": "gentle-ai", "tags": [], "created_at": "2026-08-15 10:00:00"},
              {"sync_id": "o2", "title": "T2", "content": "C2", "project": "all-in-gentle", "tags": [], "created_at": "2026-08-15 10:00:00"},
              {"sync_id": "o3", "title": "T3", "content": "C3", "project": "gentle-ai", "tags": [], "created_at": "2026-08-15 10:00:00"}
            ]
            """
            return (response, Data(json.utf8))
        }

        let projects = try await makeEngramClient().projects()

        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects.map(\.name), ["all-in-gentle", "gentle-ai"])
        XCTAssertTrue(projects.allSatisfy { $0.source == .engram })
    }

    // MARK: - Engram live smoke (opt-in)

    func testEngramLiveHealthAndSearch() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ALL_IN_GENTLE_LIVE_TESTS"] == "1",
            "live-service test skipped; set ALL_IN_GENTLE_LIVE_TESTS=1 to run"
        )

        let client = EngramClient(baseURL: engramBaseURL)
        let healthy = try await client.health()
        XCTAssertTrue(healthy)
        _ = try await client.search(query: "all-in-gentle", limit: 5)
    }
}
