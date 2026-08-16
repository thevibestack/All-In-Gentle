import Foundation
import SQLite3
import XCTest
@testable import AllInGentleKit

actor CapturingProcessRunner: ProcessRunning {
    var lastExecutable: URL?
    var lastArguments: [String] = []
    var lastTimeout: Duration?
    var nextOutput: String = ""

    func setNextOutput(_ value: String) {
        nextOutput = value
    }

    func run(executable: URL, arguments: [String], timeout: Duration = .seconds(30)) async throws -> String {
        lastExecutable = executable
        lastArguments = arguments
        lastTimeout = timeout
        return nextOutput
    }
}

final class ClientTests: XCTestCase {

    private static let sessionSeed =
        """
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            project_id TEXT,
            title TEXT,
            cost REAL,
            tokens_input INTEGER,
            tokens_output INTEGER,
            time_updated INTEGER
        );
        """

    /// Creates a hermetic temp database seeded with `seedSQL` and an `OpenCodeClient` over it.
    private func makeClient(seedSQL: String) -> (client: OpenCodeClient, dbURL: URL) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        var db: OpaquePointer?
        sqlite3_open(tempURL.path, &db)
        sqlite3_exec(db, seedSQL, nil, nil, nil)
        sqlite3_close(db)
        return (OpenCodeClient(dbPath: tempURL.path), tempURL)
    }

    func testCodeGraphClientPassesLiteralPathArgument() async {
        let runner = CapturingProcessRunner()
        let client = CodeGraphClient(runner: runner)
        let malicious = "/tmp/project with spaces; rm -rf /; $(echo owned)"
        _ = try? await client.projects(at: malicious)

        let arguments = await runner.lastArguments
        let executable = await runner.lastExecutable

        XCTAssertEqual(executable?.path, "/usr/bin/find")
        XCTAssertTrue(arguments.contains(malicious), "Path must appear as a literal argument")
        XCTAssertEqual(arguments.first, malicious, "Path must be the first literal argument")
        XCTAssertFalse(
            arguments.contains("/bin/sh") || arguments.contains("-c") || arguments.contains(";"),
            "Must not invoke a shell or concatenate arguments"
        )
    }

    func testOpenCodeClientRejectsWriteQueriesAndDoesNotMutateFile() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await client.executeReadOnly("INSERT INTO foo VALUES (1)")
            XCTFail("Write query should be rejected")
        } catch let error as AllInGentleError {
            XCTAssertEqual(error, .readOnlyViolation)
        }

        var verify: OpaquePointer?
        sqlite3_open(tempURL.path, &verify)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(verify, "SELECT COUNT(*) FROM foo", -1, &statement, nil)
        sqlite3_step(statement)
        let count = Int(sqlite3_column_int(statement, 0))
        sqlite3_finalize(statement)
        sqlite3_close(verify)
        XCTAssertEqual(count, 0, "Database file must not be mutated")
    }

    func testOpenCodeClientProjectsDeriveNameFromEmptyOpenCodeName() async throws {
        let (client, tempURL) = makeClient(
            seedSQL:
                """
                CREATE TABLE project (id TEXT PRIMARY KEY, name TEXT, worktree TEXT, time_updated INTEGER);
                INSERT INTO project VALUES ('p1', '', '/tmp/My Project', 1000);
                """
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let projects = try await client.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.name, "My Project")
        XCTAssertEqual(projects.first?.path, "/tmp/My Project")
        XCTAssertEqual(projects.first?.source, .opencode)
    }

    // MARK: - OpenCodeClient SQL parameter binding (F25)

    func testExecuteReadOnlyBindsTextParameterWithEmbeddedQuote() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let rows = try await client.executeReadOnly("SELECT ?", bind: [.text("a'b")])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text(0), "a'b", "Bound text must round-trip through the placeholder")
    }

    func testExecuteReadOnlyRejectsWriteQueryWithBindAndDoesNotMutateFile() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await client.executeReadOnly("INSERT INTO foo VALUES (?)", bind: [.int64(1)])
            XCTFail("Write query should be rejected")
        } catch let error as AllInGentleError {
            XCTAssertEqual(error, .readOnlyViolation)
        }

        var verify: OpaquePointer?
        sqlite3_open(tempURL.path, &verify)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(verify, "SELECT COUNT(*) FROM foo", -1, &statement, nil)
        sqlite3_step(statement)
        let count = Int(sqlite3_column_int(statement, 0))
        sqlite3_finalize(statement)
        sqlite3_close(verify)
        XCTAssertEqual(count, 0, "Database file must not be mutated")
    }

    func testExecuteReadOnlyThrowsWhenBindIndexOutOfRange() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await client.executeReadOnly("SELECT 1", bind: [.int64(1), .int64(2)])
            XCTFail("Binding more values than placeholders must throw")
        } catch let error as AllInGentleError {
            guard case .sourceUnavailable = error else {
                return XCTFail("Expected sourceUnavailable, got \(error)")
            }
        }
    }

    func testTokenUsagePageBindsLimitPlaceholderReturnsExactlyLimitRows() async throws {
        var seed = Self.sessionSeed
        for i in 0..<15 {
            seed += "INSERT INTO session VALUES ('s\(i)','p','t\(i)',0.1,10,20,\(1_000 + i));"
        }
        let (client, tempURL) = makeClient(seedSQL: seed)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let page = try await client.tokenUsagePage(limit: 10)

        XCTAssertEqual(page.count, 10, "LIMIT ? must return exactly 10 of 15 seeded rows")
    }

    // MARK: - OpenCodeClient typed row materialization (F25)

    func testExecuteReadOnlyMaterializesTypedColumns() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let rows = try await client.executeReadOnly("SELECT 1, 'x', 0.5, NULL")
        let row = try XCTUnwrap(rows.first)

        XCTAssertEqual(row.int64(0), 1)
        XCTAssertEqual(row.text(1), "x")
        XCTAssertEqual(row.double(2), 0.5)
        XCTAssertTrue(row.isNull(3))
    }

    func testExecuteReadOnlyPreservesRealPrecision() async throws {
        let (client, tempURL) = makeClient(seedSQL: "CREATE TABLE foo (id INTEGER PRIMARY KEY);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let rows = try await client.executeReadOnly("SELECT 0.12345678901234567")

        XCTAssertEqual(rows.first?.double(0), 0.12345678901234567)
    }

    func testTokenUsagePagePreservesRealCostPrecision() async throws {
        let (client, tempURL) = makeClient(
            seedSQL: Self.sessionSeed + "INSERT INTO session VALUES ('s1','p','t1',0.12345678901234567,10,20,1000);"
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let page = try await client.tokenUsagePage(limit: 10)

        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(
            page.first?.estimatedCost, 0.12345678901234567, "REAL cost must be read via sqlite3_column_double")
    }

    // MARK: - OpenCodeClient limit clamp + non-finite cursor guard (F25)

    func testTokenUsagePageClampsNegativeLimitToZero() async throws {
        var seed = Self.sessionSeed
        for i in 0..<5 {
            seed += "INSERT INTO session VALUES ('s\(i)','p','t\(i)',0.1,10,20,\(1_000 + i));"
        }
        let (client, tempURL) = makeClient(seedSQL: seed)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let page = try await client.tokenUsagePage(limit: -1)

        XCTAssertEqual(page.count, 0, "LIMIT -1 must clamp to 0, not fetch all rows")

        let usage = try await client.tokenUsage(limit: -1)
        XCTAssertEqual(usage.count, 0, "tokenUsage must clamp negative limit to 0 as well")
    }

    func testTokenUsagePageRejectsNonFiniteCursor() async throws {
        let (client, tempURL) = makeClient(
            seedSQL: Self.sessionSeed + "INSERT INTO session VALUES ('s1','p','t1',0.1,10,20,1000);")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        for bad in [Double.nan, Double.infinity] {
            let cursor = TokenCursor(timeUpdated: bad, id: "s1")
            do {
                _ = try await client.tokenUsagePage(after: cursor, limit: 10)
                XCTFail("Non-finite cursor should be rejected")
            } catch let error as AllInGentleError {
                XCTAssertEqual(error, .sourceUnavailable("non-finite cursor"))
            }
        }
    }

    // MARK: - OpenCodeClient placeholder-bound keyset SQL (F25)

    func testTokenUsagePageCursorAtOldestRowReturnsEmptyPage() async throws {
        var seed = Self.sessionSeed
        for i in 0..<3 {
            seed += "INSERT INTO session VALUES ('s\(i)','p','t\(i)',0.1,10,20,\(1_000 + i));"
        }
        let (client, tempURL) = makeClient(seedSQL: seed)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cursor = TokenCursor(timeUpdated: 1_000, id: "s0")
        let page = try await client.tokenUsagePage(after: cursor, limit: 10)

        XCTAssertTrue(page.isEmpty, "No rows before the oldest cursor means an empty page (S9)")
    }

    func testTokenUsagePagePreservesIdDescTieBreak() async throws {
        var seed = Self.sessionSeed
        for id in ["a", "b", "c"] {
            seed += "INSERT INTO session VALUES ('\(id)','p','t',0.1,10,20,1000);"
        }
        let (client, tempURL) = makeClient(seedSQL: seed)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let first = try await client.tokenUsagePage(limit: 2)
        XCTAssertEqual(first.map(\.id), ["c", "b"], "Equal timestamps must tie-break with id DESC (R6)")

        let second = try await client.tokenUsagePage(after: TokenCursor(timeUpdated: 1000, id: "b"), limit: 2)
        XCTAssertEqual(second.map(\.id), ["a"], "Keyset resume must return remaining rows in id DESC order (R6)")
    }

    func testProcessMonitorCanStartMonitoringSequence() async {
        let runner = CapturingProcessRunner()
        await runner.setNextOutput("")
        let monitor = ProcessMonitor(interval: .milliseconds(10), runner: runner)
        let descriptor = ServiceDescriptor(
            id: "engram",
            name: "Engram",
            processName: "engram",
            port: 7437
        )
        let stream = await monitor.updates(for: [descriptor])
        var iterator = stream.makeAsyncIterator()
        let statuses = try? await iterator.next()
        XCTAssertNotNil(statuses)
        XCTAssertEqual(statuses?.first?.id, "engram")
    }

    func testMakeAppDefaultSetsTimeoutsAndConnectivity() {
        let configuration = URLSessionConfiguration.makeAppDefault()

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 600)
        XCTAssertTrue(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 4)
        XCTAssertEqual(configuration.urlCache?.diskCapacity, 0, "Ephemeral base must not use an on-disk cache")
    }
}
