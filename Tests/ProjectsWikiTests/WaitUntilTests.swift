import XCTest
import AllInGentleTestSupport

@MainActor
final class WaitUntilTests: XCTestCase {

    func testWaitUntilReturnsTrueOnceConditionHolds() async {
        var calls = 0
        let result = await waitUntil(timeout: .seconds(1)) {
            calls += 1
            return calls >= 3
        }

        XCTAssertTrue(result)
        XCTAssertGreaterThanOrEqual(calls, 3, "helper must poll the condition, not return on first check")
    }

    func testWaitUntilReturnsFalseWhenDeadlineExpires() async {
        let start = ContinuousClock.now
        let result = await waitUntil(timeout: .milliseconds(50)) { false }
        let elapsed = start.duration(to: ContinuousClock.now)

        XCTAssertFalse(result)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(40), "helper must not return before the deadline")
    }
}
