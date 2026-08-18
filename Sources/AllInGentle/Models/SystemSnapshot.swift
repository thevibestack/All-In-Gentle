import Foundation

/// Memory pressure level reported by macOS
/// (`kern.memorystatus_vm_pressure_level`): 2 = warning, 4 = critical.
public enum MemoryPressure: String, Sendable {
    case normal
    case warning
    case critical
}

/// A single consolidated view of the system at one instant. Each metric is
/// optional so it degrades independently (baseline / unavailable / no data
/// are all `nil`) without crashing the dashboard (spec ST-9, G-5).
public struct SystemSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let cpu: CPUSnapshot?
    public let ram: RAMSnapshot?
    public let gpu: GPUSnapshot?
    public let network: NetworkSnapshot?
    public let battery: BatterySnapshot?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpu: CPUSnapshot? = nil,
        ram: RAMSnapshot? = nil,
        gpu: GPUSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        battery: BatterySnapshot? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpu = cpu
        self.ram = ram
        self.gpu = gpu
        self.network = network
        self.battery = battery
    }
}

/// CPU usage snapshot. All values are percentages in the 0...100 range.
public struct CPUSnapshot: Sendable {
    public let total: Double
    public let system: Double
    public let user: Double
    public let perCore: [Double]

    public init(total: Double, system: Double, user: Double, perCore: [Double]) {
        self.total = total
        self.system = system
        self.user = user
        self.perCore = perCore
    }
}

/// RAM usage snapshot in bytes, plus pressure level and swap totals.
public struct RAMSnapshot: Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let appBytes: UInt64
    public let cachedBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let pressure: MemoryPressure
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        appBytes: UInt64,
        cachedBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        pressure: MemoryPressure,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.appBytes = appBytes
        self.cachedBytes = cachedBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }
}

/// GPU usage snapshot. `nil` at the snapshot level means the GPU metric is
/// unavailable (Intel/AMD/VM). Values are percentages in the 0...100 range.
public struct GPUSnapshot: Sendable {
    public let utilization: Double
    public let rendererUtilization: Double?

    public init(utilization: Double, rendererUtilization: Double? = nil) {
        self.utilization = utilization
        self.rendererUtilization = rendererUtilization
    }
}

/// Network throughput snapshot for one interface, in bytes per second.
public struct NetworkSnapshot: Sendable {
    public let interfaceName: String
    public let receivedBytesPerSec: Double
    public let sentBytesPerSec: Double

    public init(interfaceName: String, receivedBytesPerSec: Double, sentBytesPerSec: Double) {
        self.interfaceName = interfaceName
        self.receivedBytesPerSec = receivedBytesPerSec
        self.sentBytesPerSec = sentBytesPerSec
    }
}

/// Battery snapshot. `level` is a percentage in the 0...100 range;
/// `timeToEmpty` is `nil` while plugged (clamped from the OS `-1` marker).
public struct BatterySnapshot: Sendable {
    public let level: Double
    public let isCharging: Bool
    public let cycleCount: Int
    public let timeToEmpty: TimeInterval?

    public init(level: Double, isCharging: Bool, cycleCount: Int, timeToEmpty: TimeInterval? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.cycleCount = cycleCount
        self.timeToEmpty = timeToEmpty
    }
}
