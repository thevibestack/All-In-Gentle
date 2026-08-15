import Foundation
import XCTest
@testable import AllInGentleKit

/// Real-subprocess tests for `ProcessRunner` (spec domain `process-running`).
/// Spawn actual `/bin` binaries; the harness is the test itself.
final class ProcessRunnerTests: XCTestCase {

    // MARK: - R1.1 Concurrent pipe drain

    func testRunReturnsFullOutputForLargeStdout() async throws {
        // A child writing >64KB to stdout must not deadlock: the drain must be
        // concurrent with execution, not sequential wait-then-read.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let payload = Data(repeating: 0x61, count: 100_000) // "a" x 100KB
        try payload.write(to: tmp)

        let runner = ProcessRunner()
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: [tmp.path],
            timeout: .seconds(10)
        )

        XCTAssertEqual(output.count, payload.count)
        XCTAssertEqual(output, String(data: payload, encoding: .utf8))
    }

    // MARK: - R1.2 Default timeout terminates child

    func testRunTimesOutAndTerminatesChild() async throws {
        let runner = ProcessRunner()
        let start = Date()
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: .milliseconds(200)
            )
            XCTFail("Expected a processTimedOut error")
        } catch let error as AllInGentleError {
            guard case .processTimedOut = error else {
                return XCTFail("Unexpected error type: \(error)")
            }
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            1.0,
            "Child must be terminated promptly after timeout"
        )
    }

    // MARK: - R1.3 Cancellation kills child

    func testRunCancellationTerminatesChildAndThrows() async throws {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: .seconds(5)
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let start = Date()
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation must surface as CancellationError.
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            1.0,
            "Cancelled run must complete promptly"
        )
    }

    // MARK: - R1.4 Success and failure status

    func testRunReturnsStdoutOnZeroExit() async throws {
        let runner = ProcessRunner()
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            timeout: .seconds(5)
        )
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    func testRunSurfacesStderrOnNonZeroExit() async throws {
        let runner = ProcessRunner()
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/cat"),
                arguments: ["/nonexistent"],
                timeout: .seconds(5)
            )
            XCTFail("Expected sourceUnavailable for non-zero exit")
        } catch let error as AllInGentleError {
            guard case .sourceUnavailable(let message) = error else {
                return XCTFail("Unexpected error type: \(error)")
            }
            XCTAssertTrue(
                message.contains("/nonexistent") || message.lowercased().contains("no such file"),
                "Failure message must surface stderr, got: \(message)"
            )
        }
    }
}
