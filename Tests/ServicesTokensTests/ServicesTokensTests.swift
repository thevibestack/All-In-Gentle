import XCTest
@testable import AllInGentleKit

final class ServicesTokensTests: XCTestCase {
    func testProcessMonitorDegradesOnPermissionDenied() async {
        let runner = PermissionDeniedRunner()
        let monitor = ProcessMonitor(interval: .seconds(1), runner: runner)
        let services = [
            ServiceDescriptor(id: "engram", name: "Engram", processName: "engram", port: 7437),
            ServiceDescriptor(id: "codegraph", name: "CodeGraph", processName: "codegraph"),
        ]

        let statuses = await monitor.statuses(for: services)

        XCTAssertEqual(statuses.count, services.count)
        for status in statuses {
            XCTAssertFalse(status.isRunning)
            XCTAssertNotNil(status.lastError)
        }
    }

    func testTokenCursorKeysetCondition() {
        let sql = Self.tokenUsagePageSQL()

        XCTAssertTrue(sql.contains("time_updated < ?"))
        XCTAssertTrue(sql.contains("id < ?"))
        XCTAssertTrue(sql.contains("ORDER BY time_updated DESC, id DESC"))
        XCTAssertTrue(sql.contains("LIMIT ?"))
    }

    // MARK: - Helpers

    private static func tokenUsagePageSQL() -> String {
        """
        SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
        FROM session
        WHERE (time_updated < ? OR (time_updated = ? AND id < ?))
        ORDER BY time_updated DESC, id DESC
        LIMIT ?
        """
    }
}

struct PermissionDeniedRunner: ProcessRunning {
    func run(executable: URL, arguments: [String], timeout: Duration = .seconds(30)) async throws -> String {
        throw AllInGentleError.sourceUnavailable("Operation not permitted")
    }
}
