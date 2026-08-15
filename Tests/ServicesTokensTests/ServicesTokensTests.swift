import XCTest
@testable import AllInGentleKit

final class ServicesTokensTests: XCTestCase {
    func testProcessMonitorDegradesOnPermissionDenied() async {
        let runner = PermissionDeniedRunner()
        let monitor = ProcessMonitor(interval: .seconds(1), runner: runner)
        let services = [
            ServiceDescriptor(id: "engram", name: "Engram", processName: "engram", port: 7437),
            ServiceDescriptor(id: "codegraph", name: "CodeGraph", processName: "codegraph")
        ]

        let statuses = await monitor.statuses(for: services)

        XCTAssertEqual(statuses.count, services.count)
        for status in statuses {
            XCTAssertFalse(status.isRunning)
            XCTAssertNotNil(status.lastError)
        }
    }

    func testTokenCursorKeysetCondition() {
        let cursor = TokenCursor(timeUpdated: 1_700_000_000_000, id: "session-b")
        let sql = Self.tokenUsagePageSQL(after: cursor, limit: 25)

        XCTAssertTrue(sql.contains("time_updated <"))
        XCTAssertTrue(sql.contains("id <"))
        XCTAssertTrue(sql.contains("ORDER BY time_updated DESC, id DESC"))
        XCTAssertTrue(sql.contains("LIMIT 25"))
    }

    // MARK: - Helpers

    private static func tokenUsagePageSQL(after cursor: TokenCursor, limit: Int) -> String {
        let escapedID = cursor.id.replacingOccurrences(of: "'", with: "''")
        return """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            WHERE (time_updated < \(cursor.timeUpdated) OR (time_updated = \(cursor.timeUpdated) AND id < '\(escapedID)'))
            ORDER BY time_updated DESC, id DESC
            LIMIT \(limit)
            """
    }
}

struct PermissionDeniedRunner: ProcessRunning {
    func run(executable: URL, arguments: [String], timeout: Duration = .seconds(30)) async throws -> String {
        throw AllInGentleError.sourceUnavailable("Operation not permitted")
    }
}
