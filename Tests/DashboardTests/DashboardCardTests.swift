import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import AllInGentleKit

/// Hermetic card tests (spec DC-1...DC-7, G-5): the per-card degradation
/// decisions are pure helpers asserted directly (battery hidden, pressure
/// badge, RAM segments, service badge incl. error rendering); card bodies
/// evaluate through `ImageRenderer`, both standalone and inside the real
/// `DashboardGrid`, so compositions run headlessly (no crash, no cross-block).
@MainActor
final class DashboardCardTests: XCTestCase {

    // MARK: - DC-5: battery card hidden while no battery exists

    func testBatteryCardHiddenUnlessSnapshotExists() {
        XCTAssertFalse(batteryCardVisible(nil))
        XCTAssertTrue(batteryCardVisible(BatterySnapshot(level: 80, isCharging: true, cycleCount: 79)))
    }

    // MARK: - DC-2: pressure badge mapping (normal=live, warning=placeholder, critical=error)

    func testPressureBadgeMapsAllThreeLevels() {
        XCTAssertEqual(memoryPressureStatus(.normal), .live)
        XCTAssertEqual(memoryPressureStatus(.warning), .placeholder)
        XCTAssertEqual(memoryPressureStatus(.critical), .error)
    }

    // MARK: - DC-2: RAM segments (app/cache/wired/compressed)

    func testRamSegmentsSplitSnapshotIntoFourKinds() {
        let ram = RAMSnapshot(
            usedBytes: 7_500_000_000, totalBytes: 16_000_000_000,
            appBytes: 4_000_000_000, cachedBytes: 2_000_000_000,
            wiredBytes: 1_000_000_000, compressedBytes: 500_000_000,
            pressure: .normal, swapUsedBytes: 100, swapTotalBytes: 200
        )
        let segments = ramSegments(from: ram)
        XCTAssertEqual(segments.map(\.kind), [.app, .cache, .wired, .compressed])
        XCTAssertEqual(segments.map(\.bytes), [4_000_000_000, 2_000_000_000, 1_000_000_000, 500_000_000])
        let fractions = memoryFractions(segments)
        XCTAssertEqual(fractions[0], 4.0 / 7.5, accuracy: 0.001)
        XCTAssertEqual(fractions[3], 0.5 / 7.5, accuracy: 0.001)
    }

    func testRamSegmentsAreEmptyWhenSnapshotIsNil() {
        XCTAssertTrue(ramSegments(from: nil).isEmpty)
    }

    // MARK: - DC-6: service badge, including error rendering

    func testServiceBadgeMapsRunningStoppedAndFailed() {
        XCTAssertEqual(serviceBadgeStatus(ServiceStatus(id: "engram", name: "Engram", isRunning: true)), .live)
        XCTAssertEqual(
            serviceBadgeStatus(ServiceStatus(id: "opencode", name: "OpenCode", isRunning: false)), .disabled)
        XCTAssertEqual(
            serviceBadgeStatus(
                ServiceStatus(id: "engram", name: "Engram", isRunning: false, lastError: "ps failed")),
            .error)
    }

    // MARK: - Render: unique composition paths (DC-1...DC-6)

    func testGpuCardRendersContentAndUnavailableWithoutCrash() {
        let gpu = GPUSnapshot(utilization: 85, rendererUtilization: 85)
        XCTAssertNotNil(renderedImage(GPUCard(phase: .content, gpu: gpu, history: [sample(85)])))
        XCTAssertNotNil(renderedImage(GPUCard(phase: .empty, gpu: nil, history: [])))
    }

    func testBatteryCardRendersGaugeBadgeAndCyclesWithoutCrash() {
        XCTAssertNotNil(
            renderedImage(BatteryCard(battery: BatterySnapshot(level: 80, isCharging: true, cycleCount: 79))))
    }

    func testServicesCardRendersStatusesAndLoadingWithoutCrash() {
        let statuses = [
            ServiceStatus(id: "engram", name: "Engram", isRunning: true),
            ServiceStatus(id: "codegraph", name: "CodeGraph", isRunning: false, lastError: "down"),
            ServiceStatus(id: "opencode", name: "OpenCode", isRunning: false),
        ]
        XCTAssertNotNil(renderedImage(ServicesCard(statuses: statuses)))
        XCTAssertNotNil(renderedImage(ServicesCard(statuses: [])))
    }

    // MARK: - DC-7 / G-5: whole grid degrades per card, never crashes

    func testGridRendersWhenEveryMetricIsUnavailable() async {
        let viewModel = DashboardViewModel(
            metrics: AllNilMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "", lsofOutput: ""))
        )
        await viewModel.refreshFastMetrics()
        await viewModel.refreshSlowMetrics()
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertEqual(viewModel.cardPhase(viewModel.cpu), .empty)
        XCTAssertNil(viewModel.battery, "battery card must be absent from the grid")
        XCTAssertNotNil(renderedImage(DashboardGrid(viewModel: viewModel), size: CGSize(width: 1200, height: 1400)))
    }

    func testGridRendersWithMixedAvailability() async {
        let viewModel = DashboardViewModel(
            metrics: MixedMetrics(),
            monitor: ProcessMonitor(runner: StubProcessRunner(psOutput: "PID COMM\n1 engram\n", lsofOutput: "42\n"))
        )
        await viewModel.refreshFastMetrics()
        await viewModel.refreshFastMetrics()
        await viewModel.refreshSlowMetrics()
        XCTAssertEqual(viewModel.cardPhase(viewModel.cpu), .content)
        XCTAssertEqual(viewModel.cardPhase(viewModel.gpu), .empty, "GPU unavailable must not block CPU content")
        XCTAssertEqual(viewModel.serviceStatuses.count, 3)
        XCTAssertNotNil(renderedImage(DashboardGrid(viewModel: viewModel), size: CGSize(width: 1200, height: 1400)))
    }

    // MARK: - Helpers

    private func sample(_ value: Double) -> MetricSample {
        MetricSample(value: value)
    }

    /// Evaluates a SwiftUI body into an offscreen image. `nil` means the body
    /// failed to produce any output (crash path).
    private func renderedImage<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.cgImage
    }
}
