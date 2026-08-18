import Foundation
import XCTest

@testable import AllInGentleKit

/// Hermetic DashboardViewModel tests (ST-7, DC-6/DC-7): ring-buffer bounding,
/// per-card degradation, services running/total — fixture readers + a stub
/// process runner: zero real hardware, zero timers.
@MainActor
final class DashboardViewModelTests: XCTestCase {

    // MARK: - D4: cadence intervals match spec (injected reads, no pinned constants)

    func testFastLoopIntervalIsOneSecondPerSpec() {
        XCTAssertEqual(DashboardViewModel.fastInterval, .seconds(1))
    }

    func testSlowLoopIntervalStaysFiveSecondsPerSpec() {
        XCTAssertEqual(DashboardViewModel.slowInterval, .seconds(5))
    }

    // MARK: - D4: display window trims at model level, no pre-aggregation

    func testDisplayedSeriesCapsAtWindowWhenBufferIsFull() {
        var history: [MetricSample] = []
        for value in 1...DashboardViewModel.historyCapacity {
            history = DashboardViewModel.appending(MetricSample(value: Double(value)), to: history)
        }
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        let displayed = viewModel.displayedSeries(history)
        XCTAssertEqual(displayed.count, DashboardViewModel.displayWindow)
        XCTAssertEqual(displayed.first?.value, 61, "only the 60 newest samples may render")
        XCTAssertEqual(displayed.last?.value, 120)
    }

    func testDisplayedSeriesKeepsAllSamplesUnderWindow() {
        var history: [MetricSample] = []
        for value in 1...30 {
            history = DashboardViewModel.appending(MetricSample(value: Double(value)), to: history)
        }
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        let displayed = viewModel.displayedSeries(history)
        XCTAssertEqual(displayed.map(\.value), (1...30).map(Double.init), "below the window no sample is dropped")
    }

    func testDisplayedSeriesKeepsAllSamplesAtWindowBoundary() {
        var history: [MetricSample] = []
        for value in 1...DashboardViewModel.displayWindow {
            history = DashboardViewModel.appending(MetricSample(value: Double(value)), to: history)
        }
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        XCTAssertEqual(viewModel.displayedSeries(history).count, 60, "exactly one window renders whole")
    }

    func testDisplayedSeriesIsEmptyWhenHistoryIsEmpty() {
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        XCTAssertTrue(viewModel.displayedSeries([]).isEmpty, "empty history renders nothing, no padding")
    }

    // MARK: - D4: ramHistory tracks RAM used % for the sparkline

    func testRefreshFastMetricsAppendsRamUsedPercentToRamHistory() async {
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),  // 8 GB used / 16 GB total
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        await viewModel.refreshFastMetrics()
        XCTAssertEqual(viewModel.ramHistory.map(\.value), [50.0], "RAM used % = usedBytes / totalBytes * 100")
    }

    func testRamHistoryStaysBoundedAndKeepsNewest() async {
        let viewModel = DashboardViewModel(
            metrics: RampingRAMMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        for _ in 1...130 {
            await viewModel.refreshFastMetrics()
        }
        XCTAssertEqual(viewModel.ramHistory.count, DashboardViewModel.historyCapacity)
        XCTAssertEqual(viewModel.ramHistory.first?.value ?? -1, 11.0, accuracy: 0.001, "oldest kept sample is tick 11")
        XCTAssertEqual(viewModel.ramHistory.last?.value ?? -1, 130.0, accuracy: 0.001, "newest tick always retained")
    }

    // MARK: - ST-7: ring buffer bounded to 120 samples

    func testAppendingKeepsHistoryBoundedAtOneTwenty() {
        var history: [MetricSample] = []
        for value in 1...3 {
            history = DashboardViewModel.appending(MetricSample(value: Double(value)), to: history)
        }
        XCTAssertEqual(history.map(\.value), [1, 2, 3], "below capacity keeps every sample")
        for value in 4...130 {
            history = DashboardViewModel.appending(MetricSample(value: Double(value)), to: history)
        }
        XCTAssertEqual(history.count, DashboardViewModel.historyCapacity)
        XCTAssertEqual(history.first?.value, 11, "oldest 10 samples must be dropped")
        XCTAssertEqual(history.last?.value, 130, "newest sample must be retained")
    }

    // MARK: - DC-7: metrics degrade per-card, never block each other

    func testNilMetricsOnlyEmptyTheirOwnCardAndHistoryAppendsInOrder() async {
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        await viewModel.refreshFastMetrics()
        await viewModel.refreshFastMetrics()
        await viewModel.refreshSlowMetrics()

        // CPU/RAM/network arrived; GPU and battery are unavailable (stub).
        XCTAssertNotNil(viewModel.cpu)
        XCTAssertNotNil(viewModel.ram)
        XCTAssertNotNil(viewModel.network)
        XCTAssertNil(viewModel.gpu)
        XCTAssertNil(viewModel.battery)
        // Each card's phase derives only from its own metric.
        XCTAssertEqual(viewModel.cardPhase(viewModel.cpu), .content)
        XCTAssertEqual(viewModel.cardPhase(viewModel.gpu), .empty)
        XCTAssertEqual(viewModel.cardPhase(viewModel.battery), .empty)
        XCTAssertTrue(viewModel.hasLoaded)
        // Histories append only non-nil samples, in order.
        XCTAssertEqual(viewModel.cpuHistory.map(\.value), [33.0, 33.0])
        XCTAssertEqual(viewModel.networkDownHistory.count, 2)
        XCTAssertEqual(viewModel.networkUpHistory.count, 2)
        XCTAssertTrue(viewModel.gpuHistory.isEmpty, "nil GPU must never append a sample")
    }

    func testAllNilMetricsNeverCrashAndStayEmpty() async {
        let viewModel = DashboardViewModel(
            metrics: AllNilMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        await viewModel.refreshFastMetrics()
        await viewModel.refreshSlowMetrics()

        XCTAssertTrue(viewModel.hasLoaded, "a fully nil batch still ends the loading phase")
        XCTAssertNil(viewModel.cpu)
        XCTAssertNil(viewModel.ram)
        XCTAssertNil(viewModel.gpu)
        XCTAssertNil(viewModel.network)
        XCTAssertNil(viewModel.battery)
        XCTAssertEqual(viewModel.cardPhase(viewModel.cpu), .empty)
        XCTAssertTrue(viewModel.cpuHistory.isEmpty)
        XCTAssertTrue(viewModel.ramHistory.isEmpty, "nil RAM must never append a sample")
        XCTAssertEqual(viewModel.serviceStatuses.count, 3, "services degrade to stopped, not crash")
        XCTAssertEqual(viewModel.runningServiceCount, 0)
    }

    // MARK: - DC-6: ProcessMonitor + 3 descriptors, running/total

    func testServicesReportRunningAndTotalAcrossThreeDescriptors() async {
        let running = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(
                runner: StubProcessRunner(psOutput: "PID COMM\n1 engram\n2 codegraph\n", lsofOutput: "42\n")
            )
        )
        await running.refreshSlowMetrics()

        XCTAssertEqual(running.serviceTotal, 3)
        XCTAssertEqual(running.serviceStatuses.count, 3)
        XCTAssertEqual(running.runningServiceCount, 2)
        XCTAssertEqual(running.serviceStatuses.first(where: { $0.id == "engram" })?.isRunning, true)
        XCTAssertEqual(running.serviceStatuses.first(where: { $0.id == "opencode" })?.isRunning, false)

        let none = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "PID COMM\n", lsofOutput: ""))
        )
        await none.refreshSlowMetrics()

        XCTAssertEqual(none.runningServiceCount, 0)
        XCTAssertEqual(none.serviceTotal, 3)
    }
}

/// Fixture reader: CPU/RAM/network present, GPU/battery unavailable.
/// Internal so the card render tests share the same hermetic fixtures.
actor MixedMetrics: SystemMetricsProviding {
    func cpu() async -> CPUSnapshot? {
        CPUSnapshot(total: 33.0, system: 11.0, user: 22.0, perCore: [33.0])
    }

    func ram() async -> RAMSnapshot? {
        RAMSnapshot(
            usedBytes: 8_000_000_000, totalBytes: 16_000_000_000,
            appBytes: 4_000_000_000, cachedBytes: 2_000_000_000,
            wiredBytes: 1_000_000_000, compressedBytes: 500_000_000,
            pressure: .normal, swapUsedBytes: 100, swapTotalBytes: 200
        )
    }

    func gpu() async -> GPUSnapshot? { nil }
    func network() async -> NetworkSnapshot? {
        NetworkSnapshot(interfaceName: "en0", receivedBytesPerSec: 1_000_000, sentBytesPerSec: 500_000)
    }

    func battery() async -> BatterySnapshot? { nil }
}

/// Stub process runner returning canned ps/lsof output (hermetic DC-6).
struct StubProcessRunner: ProcessRunning {
    let psOutput: String
    let lsofOutput: String

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> String {
        executable.lastPathComponent == "ps" ? psOutput : lsofOutput
    }
}

/// Fixture reader whose RAM usage grows 1 GB per read against a fixed 100 GB
/// total, so each fast tick produces a distinct used-% value (tick N → N%).
actor RampingRAMMetrics: SystemMetricsProviding {
    private var tick = 0

    func cpu() async -> CPUSnapshot? { nil }
    func gpu() async -> GPUSnapshot? { nil }
    func network() async -> NetworkSnapshot? { nil }
    func battery() async -> BatterySnapshot? { nil }

    func ram() async -> RAMSnapshot? {
        tick += 1
        return RAMSnapshot(
            usedBytes: UInt64(tick) * 1_000_000_000, totalBytes: 100_000_000_000,
            appBytes: 0, cachedBytes: 0, wiredBytes: 0, compressedBytes: 0,
            pressure: .normal, swapUsedBytes: 0, swapTotalBytes: 0
        )
    }
}

/// Fixture reader where every metric is unavailable (G-5).
struct AllNilMetrics: SystemMetricsProviding {
    func cpu() async -> CPUSnapshot? { nil }
    func ram() async -> RAMSnapshot? { nil }
    func gpu() async -> GPUSnapshot? { nil }
    func network() async -> NetworkSnapshot? { nil }
    func battery() async -> BatterySnapshot? { nil }
}
