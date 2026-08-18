import XCTest
@testable import AllInGentleKit

/// Hermetic SystemMetrics tests (spec G-2, ST-1/2/3): pure functions over
/// fixture page counts and tick arrays — no Mach/IOKit call from tests.
final class SystemMetricsTests: XCTestCase {

    // MARK: - SystemMetricsProviding seam (ST-1, G-2)

    func testProtocolSeamAcceptsFixtureReader() async {
        // A fixture reader must be injectable through the protocol (G-2).
        let stub = FixtureMetrics()
        let cpu = await stub.cpu()
        XCTAssertEqual(cpu?.total, 33.0)
        XCTAssertEqual(cpu?.perCore, [33.0])
        let ram = await stub.ram()
        let gpu = await stub.gpu()
        let network = await stub.network()
        let battery = await stub.battery()
        XCTAssertNil(ram)
        XCTAssertNil(gpu)
        XCTAssertNil(network)
        XCTAssertNil(battery)
    }

    func testActorReportsUnavailableMetricsAsNil() async {
        // GPU/network/battery readers land in the next batch; until then the
        // actor reports `nil` = unavailable (ST-4/5/6). Hermetic: no syscall.
        let metrics = SystemMetrics()
        let gpu = await metrics.gpu()
        let network = await metrics.network()
        let battery = await metrics.battery()
        XCTAssertNil(gpu)
        XCTAssertNil(network)
        XCTAssertNil(battery)
    }

    // MARK: - CPU delta (ST-3: first = baseline nil, then delta %)

    func testCpuFirstSampleIsBaselineAndReturnsNil() {
        let current = [CPUTickCounters(user: 1_000, system: 500, idle: 8_000, nice: 0)]
        XCTAssertNil(cpuSnapshot(from: [], to: current))
    }

    func testCpuSecondSampleComputesTotalSystemAndUserPercentages() {
        let previous = [
            CPUTickCounters(user: 1_000, system: 500, idle: 8_000, nice: 0),
            CPUTickCounters(user: 1_000, system: 500, idle: 8_000, nice: 0),
        ]
        let current = [
            CPUTickCounters(user: 1_300, system: 600, idle: 8_100, nice: 0),
            CPUTickCounters(user: 1_100, system: 550, idle: 8_350, nice: 0),
        ]
        let snapshot = cpuSnapshot(from: previous, to: current)
        XCTAssertEqual(snapshot?.total ?? -1, 55.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.user ?? -1, 40.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.system ?? -1, 15.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.perCore.count, 2)
        XCTAssertEqual(snapshot?.perCore[0] ?? -1, 80.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.perCore[1] ?? -1, 30.0, accuracy: 0.0001)
    }

    func testCpuFullIdleIntervalReportsZeroUsage() {
        let ticks = [CPUTickCounters(user: 100, system: 50, idle: 900, nice: 0)]
        let snapshot = cpuSnapshot(from: ticks, to: ticks)
        XCTAssertEqual(snapshot?.total ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.perCore.first ?? -1, 0.0, accuracy: 0.0001)
    }

    func testCpuSingleCoreFullyBusyIsOneHundredPercent() {
        let previous = [CPUTickCounters(user: 0, system: 0, idle: 1_000, nice: 0)]
        let current = [CPUTickCounters(user: 600, system: 300, idle: 1_000, nice: 0)]
        let snapshot = cpuSnapshot(from: previous, to: current)
        XCTAssertEqual(snapshot?.total ?? -1, 100.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.perCore.first ?? -1, 100.0, accuracy: 0.0001)
    }

    func testCpuRebaselinesWhenCoreCountChanges() {
        let previous = [CPUTickCounters(user: 100, system: 50, idle: 900, nice: 0)]
        let current = [
            CPUTickCounters(user: 200, system: 100, idle: 800, nice: 0),
            CPUTickCounters(user: 200, system: 100, idle: 800, nice: 0),
        ]
        XCTAssertNil(cpuSnapshot(from: previous, to: current))
    }

    // MARK: - RAM (ST-2: vm_statistics64 used, clamp 0...total)

    func testRamComputesUsedAndBreakdownFromPageCounts() {
        let counts = VMPageCounts(
            active: 1_000, inactive: 500, speculative: 100,
            wired: 200, compressed: 50, purgeable: 50, external: 10
        )
        let ram = ramSnapshot(
            counts: counts,
            pageSize: 4_096,
            totalBytes: 17_179_869_184,  // 16 GB
            pressureLevel: 1,
            swapUsedBytes: 1_000,
            swapTotalBytes: 2_000
        )
        XCTAssertEqual(ram.usedBytes, 7_331_840)
        XCTAssertEqual(ram.totalBytes, 17_179_869_184)
        XCTAssertEqual(ram.appBytes, 4_259_840)
        XCTAssertEqual(ram.cachedBytes, 2_048_000)
        XCTAssertEqual(ram.wiredBytes, 819_200)
        XCTAssertEqual(ram.compressedBytes, 204_800)
        XCTAssertEqual(ram.pressure, .normal)
        XCTAssertEqual(ram.swapUsedBytes, 1_000)
        XCTAssertEqual(ram.swapTotalBytes, 2_000)
    }

    func testRamClampsUsedToTotalWhenCountsOverflow() {
        let counts = VMPageCounts(
            active: 5_000_000, inactive: 5_000_000, speculative: 5_000_000,
            wired: 5_000_000, compressed: 5_000_000, purgeable: 0, external: 0
        )
        let ram = ramSnapshot(
            counts: counts, pageSize: 4_096, totalBytes: 8_000_000_000,
            pressureLevel: 1, swapUsedBytes: 0, swapTotalBytes: 0
        )
        XCTAssertEqual(ram.usedBytes, 8_000_000_000)
    }

    func testRamNeverUnderflowsAppBytes() {
        // purgeable + external exceed active + speculative: the app share must
        // saturate at 0 instead of trapping on UInt64 underflow.
        let counts = VMPageCounts(
            active: 10, inactive: 100, speculative: 0,
            wired: 50, compressed: 20, purgeable: 500, external: 500
        )
        let ram = ramSnapshot(
            counts: counts, pageSize: 4_096, totalBytes: 1_000_000,
            pressureLevel: 1, swapUsedBytes: 0, swapTotalBytes: 0
        )
        XCTAssertEqual(ram.appBytes, 0)
        XCTAssertEqual(ram.usedBytes, 696_320)  // (100 inactive + 50 wired + 20 compressed) pages
    }

    func testRamMapsPressureLevels() {
        let counts = VMPageCounts(
            active: 1, inactive: 1, speculative: 0,
            wired: 1, compressed: 0, purgeable: 0, external: 0
        )
        let warning = ramSnapshot(
            counts: counts, pageSize: 4_096, totalBytes: 1_000_000,
            pressureLevel: 2, swapUsedBytes: 0, swapTotalBytes: 0
        )
        let critical = ramSnapshot(
            counts: counts, pageSize: 4_096, totalBytes: 1_000_000,
            pressureLevel: 4, swapUsedBytes: 0, swapTotalBytes: 0
        )
        XCTAssertEqual(warning.pressure, .warning)
        XCTAssertEqual(critical.pressure, .critical)
    }
}

/// Fixture reader exercising the `SystemMetricsProviding` seam (G-2).
private final class FixtureMetrics: SystemMetricsProviding {
    func cpu() async -> CPUSnapshot? {
        CPUSnapshot(total: 33.0, system: 11.0, user: 22.0, perCore: [33.0])
    }

    func ram() async -> RAMSnapshot? { nil }
    func gpu() async -> GPUSnapshot? { nil }
    func network() async -> NetworkSnapshot? { nil }
    func battery() async -> BatterySnapshot? { nil }
}
