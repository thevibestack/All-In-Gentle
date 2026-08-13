import Foundation
import SQLite3
import XCTest
@testable import AllInGentleKit

actor CapturingProcessRunner: ProcessRunning {
    var lastExecutable: URL?
    var lastArguments: [String] = []
    var nextOutput: String = ""

    func setNextOutput(_ value: String) {
        nextOutput = value
    }

    func run(executable: URL, arguments: [String]) async throws -> String {
        lastExecutable = executable
        lastArguments = arguments
        return nextOutput
    }
}

final class ClientTests: XCTestCase {

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
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var writableDB: OpaquePointer?
        sqlite3_open(tempURL.path, &writableDB)
        sqlite3_exec(writableDB, "CREATE TABLE foo (id INTEGER PRIMARY KEY);", nil, nil, nil)
        sqlite3_close(writableDB)

        let client = OpenCodeClient(dbPath: tempURL.path)
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
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var writableDB: OpaquePointer?
        sqlite3_open(tempURL.path, &writableDB)
        sqlite3_exec(
            writableDB,
            """
            CREATE TABLE project (id TEXT PRIMARY KEY, name TEXT, worktree TEXT, time_updated INTEGER);
            INSERT INTO project VALUES ('p1', '', '/tmp/My Project', 1000);
            """,
            nil, nil, nil
        )
        sqlite3_close(writableDB)

        let client = OpenCodeClient(dbPath: tempURL.path)
        let projects = try await client.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.name, "My Project")
        XCTAssertEqual(projects.first?.path, "/tmp/My Project")
        XCTAssertEqual(projects.first?.source, .opencode)
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
}
