import Foundation
import XCTest
@testable import AllInGentleKit

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class EngramClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeMockURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func stubJSON(_ body: String, status: Int = 200) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
    }

    private func makeClient() -> EngramClient {
        EngramClient(
            baseURL: URL(string: "http://127.0.0.1:7437")!,
            urlSession: makeMockURLSession()
        )
    }

    /// Expected date built independently of the production formatter (UTC, gregorian).
    private func makeUTCDate(_ components: DateComponents) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }

    // MARK: - T1: full payload, numeric id, sync_id optional (R2)

    func testSearchDecodesFullPayloadWithNumericIDAndNilSyncID() async throws {
        stubJSON("""
        [
          {
            "id": 123,
            "title": "Memory title",
            "content": "Memory content",
            "project": "all-in-gentle",
            "tags": ["decode", "strict"],
            "created_at": "2026-01-02 03:04:05",
            "updated_at": "2026-01-03 04:05:06"
          }
        ]
        """)

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 1)
        let memory = try XCTUnwrap(result.first)
        XCTAssertEqual(memory.id, "123", "Numeric id must decode to its string value")
        XCTAssertEqual(memory.title, "Memory title")
        XCTAssertEqual(memory.content, "Memory content")
        XCTAssertEqual(memory.project, "all-in-gentle")
        XCTAssertEqual(memory.tags, ["decode", "strict"])
        XCTAssertEqual(
            memory.createdAt,
            makeUTCDate(DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5)),
            "created_at must parse via the shared UTC formatter"
        )
    }

    // MARK: - T2: string id, tags default, idString prefers sync_id (R2, D8)

    func testSearchDecodesStringIDDefaultsTagsAndPrefersSyncID() async throws {
        stubJSON("""
        [
          { "id": "abc-1", "title": "No sync", "content": "C" },
          { "id": "raw-id", "sync_id": "sync-42", "title": "Synced", "content": "C" }
        ]
        """)

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "abc-1", "String id must decode via the EngramID union")
        XCTAssertEqual(result[0].tags, [], "Missing tags must default to an empty array")
        XCTAssertEqual(result[1].id, "sync-42", "idString must prefer sync_id over id")
    }

    // MARK: - T3: malformed items skipped, nothing fabricated (R1/R3)

    func testSearchSkipsItemMissingTitleWithoutCrashing() async throws {
        stubJSON("""
        [
          { "id": 1, "content": "No title here" },
          { "id": 2, "title": "Valid", "content": "C" }
        ]
        """)

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 1, "Item without title must be skipped, not crash the decode")
        XCTAssertEqual(result.first?.id, "2")
    }

    func testSearchSkipsItemMissingIDWithoutFabricatingUUID() async throws {
        stubJSON("""
        [
          { "title": "No id", "content": "C" },
          { "id": 7, "title": "Valid", "content": "C" }
        ]
        """)

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 1, "Item without id must be skipped, never synthesized with UUID()")
        XCTAssertEqual(result.first?.id, "7")
    }

    func testSearchKeepsCreatedAtNilForUnparseableDate() async throws {
        stubJSON("""
        [
          { "id": 3, "title": "Bad date", "content": "C", "created_at": "not-a-date" },
          { "id": 4, "title": "Good", "content": "C", "updated_at": "2026-06-07 08:09:10" }
        ]
        """)

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 2, "Unparseable date must not drop the item")
        XCTAssertNil(result[0].createdAt, "Unparseable created_at must decode to nil, never Date()")
        XCTAssertEqual(
            result[1].createdAt,
            makeUTCDate(DateComponents(year: 2026, month: 6, day: 7, hour: 8, minute: 9, second: 10)),
            "updated_at must serve as the fallback date source"
        )
    }

    // MARK: - T4: null body and empty array (R4)

    func testSearchNullBodyDecodesToEmptyArray() async throws {
        stubJSON("null")

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 0, "Literal null body must decode to an empty array")
    }

    func testSearchEmptyArrayDecodesToEmptyArray() async throws {
        stubJSON("[]")

        let result = try await makeClient().search(query: "hello", limit: 20)

        XCTAssertEqual(result.count, 0, "Empty array must decode to an empty array")
    }
}
