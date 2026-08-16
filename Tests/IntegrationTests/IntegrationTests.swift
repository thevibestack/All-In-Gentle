import Foundation
import SQLite3
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

    // MARK: - OpenCode token usage (hermetic, temp DB)

    func testOpenCodeClientTokenUsageFromTempDB() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var writableDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempURL.path, &writableDB), SQLITE_OK)
        let sql = """
            CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, title TEXT, cost REAL,
                                  tokens_input INTEGER, tokens_output INTEGER, time_updated INTEGER);
            INSERT INTO session VALUES ('s1','all-in-gentle','Auth fix',0.25,120,30,1700000000000);
            INSERT INTO session VALUES ('s2','all-in-gentle','Wiki add',0.10,50,10,1700000001000);
            """
        XCTAssertEqual(sqlite3_exec(writableDB, sql, nil, nil, nil), SQLITE_OK)
        // Close the writer BEFORE the read-only client opens the file (SQLite locking).
        sqlite3_close(writableDB)

        let client = OpenCodeClient(dbPath: tempURL.path)
        let usage = try await client.tokenUsage(limit: 10)

        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.map(\.id), ["s2", "s1"], "Rows ordered by time_updated DESC")

        let newest = usage[0]
        XCTAssertEqual(newest.project, "all-in-gentle")
        XCTAssertEqual(newest.session, "Wiki add")
        XCTAssertEqual(newest.promptTokens, 50)
        XCTAssertEqual(newest.completionTokens, 10)
        XCTAssertEqual(newest.estimatedCost, 0.10, accuracy: 0.0001)
        XCTAssertEqual(newest.timestamp, Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertEqual(newest.rawTimeUpdated, 1_700_000_001_000.0)

        let oldest = usage[1]
        XCTAssertEqual(oldest.project, "all-in-gentle")
        XCTAssertEqual(oldest.session, "Auth fix")
        XCTAssertEqual(oldest.promptTokens, 120)
        XCTAssertEqual(oldest.completionTokens, 30)
        XCTAssertEqual(oldest.estimatedCost, 0.25, accuracy: 0.0001)
        XCTAssertEqual(oldest.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(oldest.rawTimeUpdated, 1_700_000_000_000.0)
    }

    func testTokenUsageKeysetTieBreakFromTempDB() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var writableDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempURL.path, &writableDB), SQLITE_OK)
        // Three rows sharing one time_updated: ordering must fall back to the
        // `time_updated = ? AND id < ?` tie-break (OpenCodeClient.swift).
        let sql = """
            CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, title TEXT, cost REAL,
                                  tokens_input INTEGER, tokens_output INTEGER, time_updated INTEGER);
            INSERT INTO session VALUES ('s1','p','first',0.1,10,10,1700000000000);
            INSERT INTO session VALUES ('s2','p','second',0.2,20,20,1700000000000);
            INSERT INTO session VALUES ('s3','p','third',0.3,30,30,1700000000000);
            """
        XCTAssertEqual(sqlite3_exec(writableDB, sql, nil, nil, nil), SQLITE_OK)
        // Close the writer BEFORE the read-only client opens the file (SQLite locking).
        sqlite3_close(writableDB)

        let client = OpenCodeClient(dbPath: tempURL.path)

        let page1 = try await client.tokenUsagePage(limit: 1)
        XCTAssertEqual(page1.map(\.id), ["s3"], "Newest id wins the full tie at time_updated DESC, id DESC")

        let cursor1 = TokenCursor(timeUpdated: page1[0].rawTimeUpdated!, id: page1[0].id)
        let page2 = try await client.tokenUsagePage(after: cursor1, limit: 1)
        XCTAssertEqual(
            page2.map(\.id), ["s2"],
            "Tie-break branch (time_updated = ? AND id < ?) must continue onto the same timestamp"
        )
        XCTAssertEqual(page2[0].rawTimeUpdated, cursor1.timeUpdated, "Cursor continuity: same time_updated, id advances")

        let cursor2 = TokenCursor(timeUpdated: page2[0].rawTimeUpdated!, id: page2[0].id)
        let page3 = try await client.tokenUsagePage(after: cursor2, limit: 1)
        XCTAssertEqual(page3.map(\.id), ["s1"])

        let cursor3 = TokenCursor(timeUpdated: page3[0].rawTimeUpdated!, id: page3[0].id)
        let page4 = try await client.tokenUsagePage(after: cursor3, limit: 1)
        XCTAssertTrue(page4.isEmpty, "Final page after the last id must be empty")
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
