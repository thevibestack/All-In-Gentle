import Darwin
import Foundation

// Portions of this file's RAM/CPU readers are ported from exelban/stats
// (https://github.com/exelban/stats), Copyright (c) 2019 exelban, MIT — see
// LICENSE. The delta/baseline math is factored into pure functions and every
// Mach call is confined to this actor (spec G-3).

// MARK: - Reader seam

/// Protocol-injectable system telemetry reader (spec ST-1). Reads are async,
/// returning optional snapshots; `nil` = baseline/unavailable/absent (G-5).
public protocol SystemMetricsProviding: Sendable {
    /// Current CPU usage; `nil` on the first sample (baseline, spec ST-3).
    func cpu() async -> CPUSnapshot?
    /// Current RAM usage and pressure (spec ST-2).
    func ram() async -> RAMSnapshot?
    /// Current GPU utilization; `nil` when unavailable (Intel/AMD/VM, ST-4).
    func gpu() async -> GPUSnapshot?
    /// Current network throughput; `nil` when no active interface (ST-5).
    func network() async -> NetworkSnapshot?
    /// Current battery state; `nil` on desktops without a battery (ST-6).
    func battery() async -> BatterySnapshot?
}

// MARK: - Actor

/// Live telemetry reader backed by Mach/IOKit syscalls (spec ST-1, G-3).
/// Delta state (previous CPU tick buffer) is actor-confined: created, read
/// and released inside this actor, never crossing an isolation boundary.
/// Tests exercise the pure helpers below with fixtures (G-2).
public actor SystemMetrics: SystemMetricsProviding {
    private var prevCPUTicks: processor_info_array_t?
    private var prevCPUTickCount: Int = 0

    public init() {}

    // MARK: CPU (spec ST-3)

    public func cpu() async -> CPUSnapshot? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )
        guard result == KERN_SUCCESS, let buffer = infoArray else { return nil }

        let previous = prevCPUTicks
        let previousCount = prevCPUTickCount
        prevCPUTicks = buffer
        prevCPUTickCount = Int(infoCount)

        // First sample is a baseline — no value is emitted (ST-3).
        guard let previous else { return nil }

        let coreCount = Int(cpuCount)
        let previousCounters = tickCounters(from: previous, coreCount: coreCount)
        let currentCounters = tickCounters(from: buffer, coreCount: coreCount)
        // Released only after both arrays were copied into Swift memory (G-3).
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: previous),
            vm_size_t(previousCount * MemoryLayout<integer_t>.stride)
        )
        return cpuSnapshot(from: previousCounters, to: currentCounters)
    }

    // MARK: RAM (spec ST-2)

    public func ram() async -> RAMSnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let counts = VMPageCounts(
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            external: UInt64(stats.external_page_count)
        )
        let swap = swapUsage()
        var pageSizeValue: vm_size_t = 0
        // vm_kernel_page_size is not concurrency-safe under Swift 6; use host_page_size.
        guard host_page_size(mach_host_self(), &pageSizeValue) == KERN_SUCCESS else { return nil }
        return ramSnapshot(
            counts: counts,
            pageSize: UInt64(pageSizeValue),
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            pressureLevel: memoryPressureLevel(),
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total
        )
    }

    // MARK: Skeleton (readers land in the next telemetry batch)

    // Full readers land next batch; `nil` = unavailable, the degradation path.
    public func gpu() async -> GPUSnapshot? { nil }
    public func network() async -> NetworkSnapshot? { nil }
    public func battery() async -> BatterySnapshot? { nil }

    // MARK: Mach/sysctl helpers (actor-confined, G-3)

    /// Copies per-core tick counters from a `PROCESSOR_CPU_LOAD_INFO` buffer
    /// into Swift memory (`CPU_STATE_MAX` values per core).
    private func tickCounters(from buffer: UnsafeMutablePointer<integer_t>, coreCount: Int)
        -> [CPUTickCounters]
    {
        let stateCount = Int(CPU_STATE_MAX)
        return (0..<coreCount).map { core in
            let base = buffer + (core * stateCount)
            // Reinterpret the signed import so values past Int32.max wrap modularly.
            return CPUTickCounters(
                user: UInt32(bitPattern: base[Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: base[Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: base[Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: base[Int(CPU_STATE_NICE)])
            )
        }
    }

    private func memoryPressureLevel() -> Int32 {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return level
    }

    private func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (usage.xsu_used, usage.xsu_total)
    }
}

// MARK: - Pure computation (hardware-free, fixture-testable)

/// Per-core CPU load tick counters (the four CPU_STATE_* values per processor).
struct CPUTickCounters: Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Raw `vm_statistics64` page counts (spec ST-2).
struct VMPageCounts: Sendable {
    var active: UInt64
    var inactive: UInt64
    var speculative: UInt64
    var wired: UInt64
    var compressed: UInt64
    var purgeable: UInt64
    var external: UInt64
}

/// Computes the CPU snapshot from two tick samples; `nil` when the previous
/// sample is missing (first read = baseline, ST-3) or core count changed.
/// Percentages are per-core and aggregate in 0...100; busy = user+system+nice.
func cpuSnapshot(from previous: [CPUTickCounters], to current: [CPUTickCounters]) -> CPUSnapshot? {
    guard !previous.isEmpty, previous.count == current.count else { return nil }
    let cores = zip(previous, current).map { prev, cur in
        (
            busy: cpuDelta(prev.user, cur.user) &+ cpuDelta(prev.system, cur.system)
                &+ cpuDelta(prev.nice, cur.nice),
            user: cpuDelta(prev.user, cur.user),
            system: cpuDelta(prev.system, cur.system),
            total: cpuDelta(prev.user, cur.user) &+ cpuDelta(prev.system, cur.system)
                &+ cpuDelta(prev.idle, cur.idle) &+ cpuDelta(prev.nice, cur.nice)
        )
    }
    let allTotal = cores.reduce(UInt32(0)) { $0 &+ $1.total }
    let allBusy = cores.reduce(UInt32(0)) { $0 &+ $1.busy }
    let allUser = cores.reduce(UInt32(0)) { $0 &+ $1.user }
    let allSystem = cores.reduce(UInt32(0)) { $0 &+ $1.system }
    return CPUSnapshot(
        total: cpuPercent(allBusy, allTotal),
        system: cpuPercent(allSystem, allTotal),
        user: cpuPercent(allUser, allTotal),
        perCore: cores.map { cpuPercent($0.busy, $0.total) }
    )
}

/// Computes the RAM snapshot from raw page counts (spec ST-2). Used memory
/// follows the vm_statistics64 breakdown (active + speculative + inactive +
/// wired + compressed − purgeable − external), clamped to 0...total; the app
/// share saturates at 0 instead of underflowing.
func ramSnapshot(
    counts: VMPageCounts,
    pageSize: UInt64,
    totalBytes: UInt64,
    pressureLevel: Int32,
    swapUsedBytes: UInt64,
    swapTotalBytes: UInt64
) -> RAMSnapshot {
    let appPages = saturatingSubtract(counts.active + counts.speculative, counts.purgeable + counts.external)
    let usedPages = appPages + counts.inactive + counts.wired + counts.compressed
    return RAMSnapshot(
        usedBytes: min(usedPages * pageSize, totalBytes),
        totalBytes: totalBytes,
        appBytes: appPages * pageSize,
        cachedBytes: counts.inactive * pageSize,
        wiredBytes: counts.wired * pageSize,
        compressedBytes: counts.compressed * pageSize,
        pressure: memoryPressure(from: pressureLevel),
        swapUsedBytes: swapUsedBytes,
        swapTotalBytes: swapTotalBytes
    )
}

/// Returns `lhs - rhs` clamped at zero instead of trapping on underflow.
private func saturatingSubtract(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    lhs >= rhs ? lhs - rhs : 0
}
