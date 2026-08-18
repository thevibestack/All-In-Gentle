import Darwin
import Foundation
import IOKit
import IOKit.ps

// Portions of this file's RAM/CPU/GPU/network/battery readers are ported from
// exelban/stats (https://github.com/exelban/stats), Copyright (c) 2019 exelban,
// MIT — see LICENSE. The delta/baseline math is factored into pure functions
// and every Mach/IOKit/sysctl call is confined to this actor (spec G-3).

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
    private var prevNetBytes: (rx: UInt64, tx: UInt64)?
    private var prevNetName: String?
    private var prevNetSampleAt: Date?

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

    // MARK: GPU (spec ST-4)

    /// Reads `PerformanceStatistics` from every `IOAccelerator` service; the
    /// busiest device wins, `nil` when none reported a value (ST-4, G-3).
    public func gpu() async -> GPUSnapshot? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        // IOServiceGetMatchingServices consumes the matching dictionary.
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var deviceValues: [Double] = []
        var rendererValues: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            let stats = performanceStatistics(service: current)
            if let device = stats["Device Utilization %"] { deviceValues.append(device) }
            if let renderer = stats["Renderer Utilization %"] { rendererValues.append(renderer) }
            service = IOIteratorNext(iterator)
        }
        return gpuSnapshot(deviceUtilizations: deviceValues, rendererUtilizations: rendererValues)
    }

    // MARK: Network (spec ST-5)

    /// Deltas `NET_RT_IFLIST2` 64-bit counters; baseline nil, clamp negative (ST-5).
    public func network() async -> NetworkSnapshot? {
        let samples = interfaceSamples()
        guard let primary = primaryInterface(from: samples) else { return nil }

        let now = Date()
        let previous = prevNetBytes
        let previousName = prevNetName
        let previousTime = prevNetSampleAt
        prevNetName = primary.name
        prevNetBytes = (rx: primary.rx, tx: primary.tx)
        prevNetSampleAt = now

        guard previousName == primary.name, let previous else { return nil }
        let elapsed = now.timeIntervalSince(previousTime ?? now)
        return networkSnapshot(
            interfaceName: primary.name,
            receivedDelta: clampedDelta(previous.rx, primary.rx),
            sentDelta: clampedDelta(previous.tx, primary.tx),
            elapsedSeconds: elapsed
        )
    }

    // MARK: Battery (spec ST-6)

    /// Reads the internal-battery power source (level/charging/time-to-empty)
    /// plus `AppleSmartBattery` cycle count; `nil` on desktops (ST-6).
    public func battery() async -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return nil }
        for source in list as [CFTypeRef] {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any]
            else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return batterySnapshot(
                currentCapacity: description[kIOPSCurrentCapacityKey] as? Int,
                maxCapacity: description[kIOPSMaxCapacityKey] as? Int,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                cycleCount: batteryCycleCount(),
                timeToEmptyMinutes: description[kIOPSTimeToEmptyKey] as? Int ?? -1
            )
        }
        return nil
    }

    // MARK: Mach/IOKit/sysctl helpers (actor-confined, G-3)

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

    /// Copies one accelerator's nested `PerformanceStatistics` to `Double`s.
    private func performanceStatistics(service: io_registry_entry_t) -> [String: Double] {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service, &properties, kCFAllocatorDefault, 0
        )
        guard result == KERN_SUCCESS,
            let dict = properties?.takeRetainedValue() as? [String: Any],
            let statistics = dict["PerformanceStatistics"] as? [String: Any]
        else { return [:] }
        return statistics.compactMapValues { value in
            let cfValue = value as CFTypeRef
            guard CFGetTypeID(cfValue) == CFNumberGetTypeID() else { return nil }
            let number = cfValue as! CFNumber
            var converted = 0.0
            guard CFNumberGetValue(number, .doubleType, &converted) else { return nil }
            return converted
        }
    }

    /// Enumerates up, non-loopback interfaces with 64-bit counters via
    /// `NET_RT_IFLIST2`; names come from `getifaddrs` (32-bit `if_data`).
    private func interfaceSamples() -> [(name: String, rx: UInt64, tx: UInt64)] {
        let names = interfaceNamesByIndex()
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return []
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length, alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 else { return [] }

        var samples: [(name: String, rx: UInt64, tx: UInt64)] = []
        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= length {
            let message = buffer.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self)
            let messageLength = Int(message.pointee.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }
            if message.pointee.ifm_type == UInt8(RTM_IFINFO2),
                message.pointee.ifm_flags & IFF_UP != 0,
                message.pointee.ifm_flags & IFF_LOOPBACK == 0,
                let name = names[UInt32(message.pointee.ifm_index)]
            {
                samples.append(
                    (
                        name: name,
                        rx: message.pointee.ifm_data.ifi_ibytes,
                        tx: message.pointee.ifm_data.ifi_obytes
                    ))
            }
            offset += messageLength
        }
        return samples
    }

    /// Maps interface indices to names from `getifaddrs` (AF_LINK entries).
    private func interfaceNamesByIndex() -> [UInt32: String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(first) }
        var names: [UInt32: String] = [:]
        var next: UnsafeMutablePointer<ifaddrs>? = first
        while let current = next {
            defer { next = current.pointee.ifa_next }
            guard current.pointee.ifa_addr?.pointee.sa_family == sa_family_t(AF_LINK) else {
                continue
            }
            let index = if_nametoindex(current.pointee.ifa_name)
            guard index != 0 else { continue }
            names[index] = String(cString: current.pointee.ifa_name)
        }
        return names
    }

    /// Reads `CycleCount` from `AppleSmartBattery`; `0` when absent.
    private func batteryCycleCount() -> Int {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return 0 }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
            let dict = properties?.takeRetainedValue() as? [String: Any]
        else { return 0 }
        return dict["CycleCount"] as? Int ?? 0
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

/// Computes the GPU snapshot from per-accelerator `PerformanceStatistics`
/// percentages (spec ST-4). Picks the busiest accelerator, clamps to 0...100,
/// and returns `nil` when no accelerator reported a value (unavailable).
func gpuSnapshot(deviceUtilizations: [Double], rendererUtilizations: [Double]) -> GPUSnapshot? {
    guard let device = deviceUtilizations.max() else { return nil }
    let utilization = min(max(device, 0), 100)
    guard let renderer = rendererUtilizations.max() else {
        return GPUSnapshot(utilization: utilization, rendererUtilization: nil)
    }
    return GPUSnapshot(
        utilization: utilization, rendererUtilization: min(max(renderer, 0), 100)
    )
}

/// Picks the primary interface sample — the busiest by cumulative bytes — or
/// `nil` when no eligible interface exists (spec ST-5 no-data path).
func primaryInterface(from samples: [(name: String, rx: UInt64, tx: UInt64)])
    -> (name: String, rx: UInt64, tx: UInt64)?
{
    samples.max { $0.rx + $0.tx < $1.rx + $1.tx }
}

/// Computes throughput rates from a cumulative-byte delta and the elapsed
/// interval (spec ST-5). Negative deltas clamp to `0` upstream via
/// `clampedDelta`; a non-positive interval yields zero rates, never a NaN.
func networkSnapshot(
    interfaceName: String,
    receivedDelta: UInt64,
    sentDelta: UInt64,
    elapsedSeconds: TimeInterval
) -> NetworkSnapshot {
    guard elapsedSeconds > 0 else {
        return NetworkSnapshot(
            interfaceName: interfaceName, receivedBytesPerSec: 0, sentBytesPerSec: 0
        )
    }
    return NetworkSnapshot(
        interfaceName: interfaceName,
        receivedBytesPerSec: Double(receivedDelta) / elapsedSeconds,
        sentBytesPerSec: Double(sentDelta) / elapsedSeconds
    )
}

/// Computes the battery snapshot from raw power-source values (spec ST-6).
/// Missing or zero max capacity → `nil` (no usable level); a `-1`
/// time-to-empty (plugged) becomes `nil`; level clamps to 0...100.
func batterySnapshot(
    currentCapacity: Int?,
    maxCapacity: Int?,
    isCharging: Bool,
    cycleCount: Int,
    timeToEmptyMinutes: Int
) -> BatterySnapshot? {
    guard let current = currentCapacity, let maximum = maxCapacity, maximum > 0 else { return nil }
    let level = min(max(Double(current) / Double(maximum) * 100, 0), 100)
    let timeToEmpty =
        timeToEmptyMinutes == -1
        ? nil
        : TimeInterval(max(0, timeToEmptyMinutes) * 60)
    return BatterySnapshot(
        level: level,
        isCharging: isCharging,
        cycleCount: cycleCount,
        timeToEmpty: timeToEmpty
    )
}
