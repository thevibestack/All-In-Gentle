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

    // MARK: - 3.3: latestDelta (D3) — newest minus previous, nil below two samples

    func testLatestDeltaIsNilWithZeroOrOneSample() {
        XCTAssertNil(latestDelta([]))
        XCTAssertNil(latestDelta([sample(42)]))
    }

    func testLatestDeltaIsLastMinusSecondLast() {
        XCTAssertEqual(latestDelta([sample(10), sample(12)]), 2)
        XCTAssertEqual(latestDelta([sample(10), sample(12), sample(9)]), -3)
    }

    // MARK: - 3.3: delta captions (D3) — signed, hidden when no delta exists

    func testDeltaCaptionFormatsSignedPercentage() {
        XCTAssertEqual(deltaCaption(3.2), "+3.2%")
        XCTAssertEqual(deltaCaption(-1.5), "-1.5%")
        XCTAssertNil(deltaCaption(nil))
    }

    func testRateDeltaCaptionFormatsSignedRate() {
        XCTAssertEqual(rateDeltaCaption(1_572_864), "+1.5 MB/s")
        XCTAssertEqual(rateDeltaCaption(-1024), "-1.0 KB/s")
        XCTAssertNil(rateDeltaCaption(nil))
    }

    // MARK: - 3.1: anatomy render phases (D3) — content / empty / single-sample

    func testCpuCardRendersContentEmptyAndSingleSampleWithoutCrash() {
        let cpu = CPUSnapshot(total: 42, system: 10, user: 20, perCore: [10, 20, 30])
        XCTAssertNotNil(renderedImage(CPUCard(phase: .content, cpu: cpu, history: samples(1...5))))
        XCTAssertNotNil(renderedImage(CPUCard(phase: .empty, cpu: nil, history: [])))
        XCTAssertNotNil(renderedImage(CPUCard(phase: .content, cpu: cpu, history: [sample(42)])))
    }

    func testRamCardRendersContentEmptyAndSingleSampleWithoutCrash() {
        let ram = RAMSnapshot(
            usedBytes: 7_500_000_000, totalBytes: 16_000_000_000,
            appBytes: 4_000_000_000, cachedBytes: 2_000_000_000,
            wiredBytes: 1_000_000_000, compressedBytes: 500_000_000,
            pressure: .normal, swapUsedBytes: 100, swapTotalBytes: 200
        )
        XCTAssertNotNil(renderedImage(RAMCard(phase: .content, ram: ram, history: samples(1...5))))
        XCTAssertNotNil(renderedImage(RAMCard(phase: .empty, ram: nil, history: [])))
        XCTAssertNotNil(renderedImage(RAMCard(phase: .content, ram: ram, history: [sample(50)])))
    }

    func testGpuCardRendersContentEmptyAndSingleSampleWithoutCrash() {
        let gpu = GPUSnapshot(utilization: 85, rendererUtilization: 85)
        XCTAssertNotNil(renderedImage(GPUCard(phase: .content, gpu: gpu, history: samples(1...5))))
        XCTAssertNotNil(renderedImage(GPUCard(phase: .empty, gpu: nil, history: [])))
        XCTAssertNotNil(renderedImage(GPUCard(phase: .content, gpu: gpu, history: [sample(85)])))
    }

    func testNetworkCardRendersContentEmptyAndSingleSampleWithoutCrash() {
        let network = NetworkSnapshot(
            interfaceName: "en0", receivedBytesPerSec: 1_000_000, sentBytesPerSec: 500_000)
        XCTAssertNotNil(
            renderedImage(
                NetworkCard(
                    phase: .content, network: network,
                    downHistory: samples(1...5), upHistory: samples(6...10))))
        XCTAssertNotNil(
            renderedImage(NetworkCard(phase: .empty, network: nil, downHistory: [], upHistory: [])))
        XCTAssertNotNil(
            renderedImage(
                NetworkCard(
                    phase: .content, network: network,
                    downHistory: [sample(10)], upHistory: [sample(20)])))
    }

    // MARK: - Helpers

    private func sample(_ value: Double) -> MetricSample {
        MetricSample(value: value)
    }

    /// A monotonically increasing series, mimicking a ticked history buffer.
    private func samples(_ values: ClosedRange<Int>) -> [MetricSample] {
        values.map { MetricSample(value: Double($0)) }
    }

    /// Evaluates a SwiftUI body into an offscreen image. `nil` means the body
    /// failed to produce any output (crash path).
    private func renderedImage<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.cgImage
    }
}
