import Foundation
import XCTest
@testable import AllInGentleKit

/// Pure, hardware-free metric helpers and value models (spec ST-8/ST-9).
/// No Mach/IOKit calls — these functions are deterministic over their inputs.
final class MetricsMathTests: XCTestCase {

    // MARK: - clampedDelta (ST-5: counter reset clamps to 0)

    func testClampedDeltaReturnsDifferenceWhenCounterAdvances() {
        XCTAssertEqual(clampedDelta(100, 150), 50)
    }

    func testClampedDeltaReturnsZeroOnCounterReset() {
        XCTAssertEqual(clampedDelta(150, 100), 0)
    }

    func testClampedDeltaReturnsZeroOnEqualCounters() {
        XCTAssertEqual(clampedDelta(80, 80), 0)
    }

    // MARK: - cpuDelta (overflow-safe tick deltas, ST-3)

    func testCpuDeltaReturnsPlainDifference() {
        XCTAssertEqual(cpuDelta(100, 250), 150)
    }

    func testCpuDeltaWrapsAroundUInt32Overflow() {
        // (10 &- (UInt32.max - 10)) mod 2^32 == 21 — the same wrapping
        // behaviour as the C `cur - prev` tick idiom.
        XCTAssertEqual(cpuDelta(UInt32.max - 10, 10), 21)
    }

    func testCpuDeltaZeroWhenTicksDidNotMove() {
        XCTAssertEqual(cpuDelta(4_000_000_000, 4_000_000_000), 0)
    }

    // MARK: - cpuPercent (ST-3)

    func testCpuPercentComputesDeltaOverTotal() {
        XCTAssertEqual(cpuPercent(30, 60), 50.0, accuracy: 0.0001)
    }

    func testCpuPercentFullUsage() {
        XCTAssertEqual(cpuPercent(200, 200), 100.0, accuracy: 0.0001)
    }

    func testCpuPercentZeroWhenTotalIsZero() {
        XCTAssertEqual(cpuPercent(10, 0), 0.0)
    }

    // MARK: - memoryPressure (ST-8: 2=warning, 4=critical, else normal)

    func testMemoryPressureMapsNormalLevel() {
        XCTAssertEqual(memoryPressure(from: 1), .normal)
    }

    func testMemoryPressureMapsWarningLevel() {
        XCTAssertEqual(memoryPressure(from: 2), .warning)
    }

    func testMemoryPressureMapsCriticalLevel() {
        XCTAssertEqual(memoryPressure(from: 4), .critical)
    }

    func testMemoryPressureMapsUnknownLevelToNormal() {
        XCTAssertEqual(memoryPressure(from: 0), .normal)
        XCTAssertEqual(memoryPressure(from: 99), .normal)
        XCTAssertEqual(memoryPressure(from: -1), .normal)
    }

    func testMemoryPressureRawValues() {
        XCTAssertEqual(MemoryPressure.normal.rawValue, "normal")
        XCTAssertEqual(MemoryPressure.warning.rawValue, "warning")
        XCTAssertEqual(MemoryPressure.critical.rawValue, "critical")
    }

    // MARK: - formatBytes (ST-8)

    func testFormatBytesShowsBytes() {
        XCTAssertEqual(formatBytes(512), "512.0 B")
    }

    func testFormatBytesShowsKilobytes() {
        XCTAssertEqual(formatBytes(1024), "1.0 KB")
    }

    func testFormatBytesShowsMegabytes() {
        XCTAssertEqual(formatBytes(1_048_576), "1.0 MB")
    }

    func testFormatBytesShowsGigabytes() {
        XCTAssertEqual(formatBytes(17_179_869_184), "16.0 GB")
    }

    func testFormatBytesShowsTerabytes() {
        XCTAssertEqual(formatBytes(1_099_511_627_776), "1.0 TB")
    }

    // MARK: - formatRate (ST-8)

    func testFormatRateShowsMegaBytesPerSecond() {
        XCTAssertEqual(formatRate(1_258_291.2), "1.2 MB/s")
    }

    func testFormatRateShowsZeroRate() {
        XCTAssertEqual(formatRate(0), "0.0 B/s")
    }

    // MARK: - formatDuration (ST-8 / battery time-to-empty)

    func testFormatDurationShowsSecondsUnderOneMinute() {
        XCTAssertEqual(formatDuration(45), "45s")
    }

    func testFormatDurationShowsZero() {
        XCTAssertEqual(formatDuration(0), "0s")
    }

    func testFormatDurationShowsMinutesUnderOneHour() {
        XCTAssertEqual(formatDuration(125), "2m")
    }

    func testFormatDurationShowsHoursAndMinutes() {
        XCTAssertEqual(formatDuration(3661), "1h 1m")
    }

    func testFormatDurationDropsZeroMinutes() {
        XCTAssertEqual(formatDuration(3600), "1h")
    }

    // MARK: - Model contract (ST-9: Identifiable + Sendable value types)

    func testMetricSamplePreservesIdentityAndValue() {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = MetricSample(id: id, timestamp: timestamp, value: 42.5)
        XCTAssertEqual(sample.id, id)
        XCTAssertEqual(sample.timestamp, timestamp)
        XCTAssertEqual(sample.value, 42.5)
    }

    func testSystemSnapshotHoldsPerMetricSnapshots() {
        let cpu = CPUSnapshot(total: 12.5, system: 4.0, user: 8.5, perCore: [10.0, 20.0])
        let ram = RAMSnapshot(
            usedBytes: 8_000_000_000,
            totalBytes: 16_000_000_000,
            appBytes: 1,
            cachedBytes: 2,
            wiredBytes: 3,
            compressedBytes: 4,
            pressure: .warning,
            swapUsedBytes: 0,
            swapTotalBytes: 1
        )
        let snapshot = SystemSnapshot(cpu: cpu, ram: ram, gpu: nil, network: nil, battery: nil)
        XCTAssertEqual(snapshot.cpu?.total, 12.5)
        XCTAssertEqual(snapshot.cpu?.perCore, [10.0, 20.0])
        XCTAssertEqual(snapshot.ram?.usedBytes, 8_000_000_000)
        XCTAssertEqual(snapshot.ram?.pressure, .warning)
        XCTAssertNil(snapshot.gpu)
        XCTAssertNil(snapshot.network)
        XCTAssertNil(snapshot.battery)
    }
}
