import Foundation
import XCTest
@testable import AllInGentleKit
import AllInGentleTestSupport

final class EngramClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeMockURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func stubJSON(
        _ body: String,
        status: Int = 200,
        onRequest: ((URLRequest) -> Void)? = nil
    ) {
        MockURLProtocol.box.set { request in
            onRequest?(request)
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
        stubJSON(
            """
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
        stubJSON(
            """
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
        stubJSON(
            """
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
        stubJSON(
            """
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
        stubJSON(
            """
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

    // MARK: - T5: 2-arg search sends q+limit only; 3-arg adds project (R5)

    func testSearchTwoArgSendsOnlyQueryAndLimit() async throws {
        var captured: URLRequest?
        stubJSON("[]") { captured = $0 }

        _ = try await makeClient().search(query: "hello world", limit: 20)

        let request = try XCTUnwrap(captured, "2-arg search must issue a request")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true))
        XCTAssertEqual(components.path, "/search")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.count, 2, "2-arg search must send exactly q and limit")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "hello world")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
        XCTAssertNil(items.first { $0.name == "project" }, "2-arg search must not send project")
    }

    func testSearchThreeArgSendsProjectAsLastPathComponent() async throws {
        var captured: URLRequest?
        stubJSON("[]") { captured = $0 }

        _ = try await makeClient().search(
            query: "note",
            limit: 50,
            project: "/Users/jesuslizarragapena/TRAZO-SOFTWARE/All-In-Gentle"
        )

        let request = try XCTUnwrap(captured)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true))
        XCTAssertEqual(components.path, "/search")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "note")
        XCTAssertEqual(
            items.first { $0.name == "project" }?.value,
            "All-In-Gentle",
            "R5: project must be the last path component, not the full path"
        )
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "50")
    }

    // MARK: - T6: observations(project:) and projects() request shapes (R5/R6)

    func testObservationsSendsProjectLastPathComponentAndLimit() async throws {
        var captured: URLRequest?
        stubJSON("[]") { captured = $0 }

        _ = try await makeClient().observations(project: "/path/all-in-gentle")

        let request = try XCTUnwrap(captured)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true))
        XCTAssertEqual(components.path, "/observations")
        let items = components.queryItems ?? []
        XCTAssertEqual(
            items.first { $0.name == "project" }?.value,
            "all-in-gentle",
            "R5: observations must send project=<lastPathComponent>"
        )
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
        XCTAssertNil(items.first { $0.name == "q" }, "observations must never send q")
    }

    func testObservationsWithExplicitLimitAndDifferentProject() async throws {
        var captured: URLRequest?
        stubJSON("[]") { captured = $0 }

        _ = try await makeClient().observations(project: "/Users/me/Repo-Space", limit: 200)

        let request = try XCTUnwrap(captured)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true))
        XCTAssertEqual(components.path, "/observations")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "project" }?.value, "Repo-Space")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "200", "explicit limit must be forwarded")
        XCTAssertNil(items.first { $0.name == "q" })
    }

    func testProjectsRequestsObservationsWithLimitThousandAndNoQuery() async throws {
        var captured: URLRequest?
        stubJSON(
            """
            [
              { "id": 1, "title": "A", "content": "C", "project": "alpha" },
              { "id": 2, "title": "B", "content": "C", "project": "beta" },
              { "id": 3, "title": "C", "content": "C", "project": "alpha" }
            ]
            """
        ) { captured = $0 }

        let projects = try await makeClient().projects()

        let request = try XCTUnwrap(captured)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true))
        XCTAssertEqual(components.path, "/observations")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.count, 1, "projects() must send only limit")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "1000")
        XCTAssertNil(items.first { $0.name == "q" }, "R6: projects() must never send q")
        XCTAssertNil(items.first { $0.name == "project" })
        XCTAssertEqual(projects.map(\.name), ["alpha", "beta"], "R6: non-empty deduplicated project list")
    }

    // MARK: - T7: empty-q 3-arg search throws before any request (D9)

    func testSearchThreeArgEmptyQueryThrowsBeforeAnyRequest() async throws {
        var requestsMade = 0
        stubJSON("[]") { _ in requestsMade += 1 }

        let client = makeClient()
        do {
            _ = try await client.search(query: "", limit: 20, project: "/path/all-in-gentle")
            XCTFail("Empty q with a project must throw invalidConfiguration")
        } catch let error as AllInGentleError {
            XCTAssertEqual(error, .invalidConfiguration("Engram search requires non-empty q"))
        }

        XCTAssertEqual(
            requestsMade,
            0,
            "D9: no request may be made for an empty q"
        )
    }
}
