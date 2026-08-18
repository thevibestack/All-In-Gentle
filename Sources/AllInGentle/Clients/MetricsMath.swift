import Foundation

// MARK: - Delta helpers

/// Returns the delta between two cumulative counter samples, clamped to
/// `0` when the counter reset (e.g. network byte counters wrapping or an
/// interface restart). A negative delta is never surfaced (spec ST-5).
func clampedDelta(_ prev: UInt64, _ cur: UInt64) -> UInt64 {
    cur >= prev ? cur - prev : 0
}

/// Returns the overflow-safe tick delta between two CPU load tick samples.
/// CPU ticks are `UInt32` counters that wrap; `&-` reproduces the modular
/// `cur - prev` behaviour of the C tick idiom (spec ST-3).
func cpuDelta(_ prev: UInt32, _ cur: UInt32) -> UInt32 {
    cur &- prev
}

/// Returns the CPU usage percentage for `delta` busy ticks out of `total`
/// ticks. Returns `0` when `total` is `0` so a not-yet-sampled series never
/// divides by zero.
func cpuPercent(_ delta: UInt32, _ total: UInt32) -> Double {
    guard total > 0 else { return 0 }
    return Double(delta) / Double(total) * 100
}

// MARK: - Memory pressure mapping

/// Maps the macOS memory-pressure sysctl level to `MemoryPressure`
/// (spec ST-8): `2` = warning, `4` = critical, anything else = normal.
func memoryPressure(from level: Int32) -> MemoryPressure {
    switch level {
    case 2:
        return .warning
    case 4:
        return .critical
    default:
        return .normal
    }
}

// MARK: - Formatting helpers

/// Byte-unit tiers with their 1024-based divisors, largest first.
private let byteTiers: [(divisor: Double, suffix: String)] = [
    (1024 * 1024 * 1024 * 1024, "TB"),
    (1024 * 1024 * 1024, "GB"),
    (1024 * 1024, "MB"),
    (1024, "KB"),
]

/// Formats a byte count as "16.0 GB" — one decimal place, 1024-based units.
private func formattedByteCount(_ value: Double) -> String {
    for tier in byteTiers where value >= tier.divisor {
        return String(format: "%.1f %@", value / tier.divisor, tier.suffix)
    }
    return String(format: "%.1f B", value)
}

/// Formats a byte count as a human-readable string, e.g. "16.0 GB" (ST-8).
func formatBytes(_ bytes: UInt64) -> String {
    formattedByteCount(Double(bytes))
}

/// Formats a transfer rate, e.g. "1.2 MB/s" (ST-8).
func formatRate(_ bytesPerSec: Double) -> String {
    formattedByteCount(bytesPerSec) + "/s"
}

/// Formats a duration as "1h 30m", "2m" or "45s" (ST-8; battery
/// time-to-empty display). Negative or fractional input clamps to zero
/// whole seconds.
func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds))
    if totalSeconds < 60 {
        return "\(totalSeconds)s"
    }
    let minutes = totalSeconds / 60
    if minutes < 60 {
        return "\(minutes)m"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}
