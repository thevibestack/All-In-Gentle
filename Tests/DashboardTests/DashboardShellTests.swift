import XCTest

@testable import AllInGentleKit

/// Shell wiring tests for the dashboard tab (spec DS-1/DS-3).
final class DashboardShellTests: XCTestCase {

    // MARK: - DS-1: AppTab.dashboard case, gauge icon, tab.dashboard key

    func testDashboardTabIsSeventhCaseWithGaugeIconAndTabDashboardKey() {
        XCTAssertEqual(AppState.AppTab.allCases.count, 7, "one tab per shortcut ⌘1...⌘7")
        XCTAssertEqual(AppState.AppTab.allCases.last, .dashboard)
        XCTAssertEqual(AppState.AppTab.dashboard.icon, "gauge")
        XCTAssertEqual(AppState.AppTab.dashboard.titleKey, "tab.dashboard")
    }

    // MARK: - DS-3: adaptive grid, minimum column 280pt

    func testGridColumnsAreAdaptiveAtMinimumTwoEighty() {
        let columns = dashboardGridColumns()
        XCTAssertEqual(columns.count, 1, "one adaptive column definition drives all columns")
        guard case .adaptive(minimum: let minimum, maximum: _) = columns[0].size else {
            return XCTFail("expected an adaptive grid item, got \(columns[0].size)")
        }
        XCTAssertEqual(minimum, 280)
    }
}
