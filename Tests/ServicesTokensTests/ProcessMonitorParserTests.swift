import Foundation
import XCTest
@testable import AllInGentleKit

/// Pins the ps/lsof parsers extracted from `ProcessMonitor` as internal pure
/// functions (R-4.1–R-4.4).
///
/// Hermetic by construction: no live /bin/ps or /usr/sbin/lsof process runs —
/// the parsers operate on captured output strings only.
final class ProcessMonitorParserTests: XCTestCase {
    // MARK: - pidValue (R-4.2 / S-4.1–S-4.3)

    func testPidValueFindsExactCommMatchInMultilineOutput() {
        let rows: [(name: String, output: String, processName: String, expected: Int?)] = [
            (
                name: "exact comm in middle line",
                output: "  PID COMM\n  1234 engram\n  5678 codegraph\n",
                processName: "engram",
                expected: 1234
            ),
            (
                name: "exact comm in last line",
                output: "  PID COMM\n  1234 engram\n  5678 codegraph\n",
                processName: "codegraph",
                expected: 5678
            ),
        ]

        for row in rows {
            XCTAssertEqual(
                pidValue(from: row.output, processName: row.processName),
                row.expected,
                "pidValue(\(row.name))"
            )
        }
    }

    func testPidValueMatchesCommBasenameAgainstProcessName() {
        let rows: [(name: String, output: String, processName: String, expected: Int?)] = [
            (
                name: "standard bin path",
                output: "  PID COMM\n  4321 /usr/bin/engram\n",
                processName: "engram",
                expected: 4321
            ),
            (
                name: "homebrew path with dash in name",
                output: "  PID COMM\n  9876 /opt/homebrew/bin/engram-server\n",
                processName: "engram-server",
                expected: 9876
            ),
        ]

        for row in rows {
            XCTAssertEqual(
                pidValue(from: row.output, processName: row.processName),
                row.expected,
                "pidValue(\(row.name))"
            )
        }
    }

    func testPidValueSkipsMalformedLinesAndFindsLaterMatch() {
        // Short (non-numeric) and blank lines are skipped; a later valid line
        // still yields its pid.
        let output = "  PID COMM\n  notanumber\n  \n  4321 engram\n"
        XCTAssertEqual(pidValue(from: output, processName: "engram"), 4321)
    }

    func testPidValueReturnsNilWhenNoLineMatches() {
        let output = "  PID COMM\n  1111 other\n  2222 another\n"
        XCTAssertNil(pidValue(from: output, processName: "engram"))
    }

    func testPidValueReturnsNilWhenMatchingCommHasNonNumericPid() {
        // Pins current `return Int(pidString)` behavior: a comm match with a
        // non-numeric pid yields nil immediately, without scanning later lines.
        let output = "  PID COMM\n  abc engram\n  9999 other\n"
        XCTAssertNil(pidValue(from: output, processName: "engram"))
    }

    // MARK: - isPortListening (R-4.3 / S-4.4)

    func testIsPortListeningMapsNonEmptyOutputToTrue() {
        let rows: [(name: String, output: String, expected: Bool)] = [
            (name: "single pid line", output: "123\n", expected: true),
            (name: "multiple pid lines", output: "123\n456\n", expected: true),
        ]

        for row in rows {
            XCTAssertEqual(isPortListening(row.output), row.expected, "isPortListening(\(row.name))")
        }
    }

    func testIsPortListeningMapsEmptyOrWhitespaceOutputToFalse() {
        let rows: [(name: String, output: String, expected: Bool)] = [
            (name: "empty string", output: "", expected: false),
            (name: "whitespace only", output: "  \n", expected: false),
        ]

        for row in rows {
            XCTAssertEqual(isPortListening(row.output), row.expected, "isPortListening(\(row.name))")
        }
    }

    // MARK: - parseElapsedTime (R-4.4 / S-4.5)

    func testParseElapsedTimeParsesSupportedFormats() {
        let rows: [(name: String, value: String, expected: TimeInterval?)] = [
            // 3 days + 2 hours + 1 minute + 5 seconds = 266465s.
            (name: "days-hours-minutes-seconds", value: "3-02:01:05", expected: 266_465),
            (name: "hours-minutes-seconds", value: "01:02:03", expected: 3_723),
            (name: "minutes-seconds", value: "05:30", expected: 330),
            (name: "single day", value: "1-00:00:00", expected: 86_400),
            (name: "whitespace padding", value: "  05:30  ", expected: 330),
        ]

        for row in rows {
            XCTAssertEqual(
                parseElapsedTime(row.value),
                row.expected,
                "parseElapsedTime(\(row.name))"
            )
        }
    }

    func testParseElapsedTimeReturnsNilForEmptyInput() {
        XCTAssertNil(parseElapsedTime(""))
    }

    func testParseElapsedTimeReturnsZeroForGarbageInput() {
        // Pins current behavior: unparseable content yields 0, not nil (R-4.4).
        XCTAssertEqual(parseElapsedTime("garbage"), 0)
    }
}
