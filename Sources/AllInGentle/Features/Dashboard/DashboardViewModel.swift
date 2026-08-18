import Foundation
import Observation

/// Per-card phase, derived per metric so one metric's unavailability never
/// blocks the others (spec DC-7, G-5).
public enum DashboardCardPhase: Equatable, Sendable {
    case loading  // no fast batch completed yet
    case content  // metric has a current value
    case empty  // metric unavailable (nil read)
}

/// Drives the dashboard grid: telemetry readers via the injectable
/// `SystemMetricsProviding` seam (G-2) + ProcessMonitor service status, two
/// `AsyncTimerSequence` cadence loops, and bounded ring buffers (ST-7).
@MainActor
@Observable
public final class DashboardViewModel {
    /// Maximum history length per chart series (spec ST-7: bounded 60–120).
    public static let historyCapacity = 120
    /// Fast-metric cadence: CPU/RAM/GPU/network (~1s, spec D4).
    public static let fastInterval: Duration = .seconds(1)
    /// Slow-metric cadence: battery + services (~5s, ST-7).
    public static let slowInterval: Duration = .seconds(5)
    /// Number of newest samples each chart renders (spec D4: window 60–90,
    /// trimmed at model level, no pre-aggregation).
    public static let displayWindow = 60
    /// The three Gentle services surfaced by the services card (DC-6).
    public static let defaultServices: [ServiceDescriptor] = [
        ServiceDescriptor(id: "engram", name: "Engram", processName: "engram", port: 7437),
        ServiceDescriptor(id: "codegraph", name: "CodeGraph", processName: "codegraph"),
        ServiceDescriptor(id: "opencode", name: "OpenCode", processName: "opencode"),
    ]

    public private(set) var cpu: CPUSnapshot?
    public private(set) var cpuHistory: [MetricSample] = []
    public private(set) var ram: RAMSnapshot?
    public private(set) var ramHistory: [MetricSample] = []
    public private(set) var gpu: GPUSnapshot?
    public private(set) var gpuHistory: [MetricSample] = []
    public private(set) var network: NetworkSnapshot?
    public private(set) var networkDownHistory: [MetricSample] = []
    public private(set) var networkUpHistory: [MetricSample] = []
    public private(set) var battery: BatterySnapshot?
    public private(set) var serviceStatuses: [ServiceStatus] = []
    /// False until the first fast batch completes (cards render `.loading`).
    public private(set) var hasLoaded: Bool = false

    public var runningServiceCount: Int { serviceStatuses.filter(\.isRunning).count }
    public var serviceTotal: Int { services.count }

    private let metrics: any SystemMetricsProviding
    private let monitor: ProcessMonitor
    private let services: [ServiceDescriptor]
    private var fastTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?

    public init(
        metrics: any SystemMetricsProviding = SystemMetrics(),
        monitor: ProcessMonitor = ProcessMonitor(),
        services: [ServiceDescriptor] = DashboardViewModel.defaultServices
    ) {
        self.metrics = metrics
        self.monitor = monitor
        self.services = services
    }

    /// Starts the two cadence loops; ignored while already running.
    public func start() {
        guard fastTask == nil, slowTask == nil else { return }
        hasLoaded = false
        fastTask = Task { [weak self] in await self?.runFastLoop() }
        slowTask = Task { [weak self] in await self?.runSlowLoop() }
    }

    /// Stops both cadence loops (view disappeared).
    public func stop() {
        fastTask?.cancel()
        slowTask?.cancel()
        fastTask = nil
        slowTask = nil
    }

    /// One fast tick: reads CPU/RAM/GPU/network independently, appending
    /// non-nil values to bounded histories (DC-7).
    public func refreshFastMetrics() async {
        if let cpu = await metrics.cpu() {
            self.cpu = cpu
            cpuHistory = Self.appending(MetricSample(value: cpu.total), to: cpuHistory)
        }
        if let ram = await metrics.ram() {
            self.ram = ram
            if let usedPercent = Self.ramUsedPercent(ram) {
                ramHistory = Self.appending(MetricSample(value: usedPercent), to: ramHistory)
            }
        }
        if let gpu = await metrics.gpu() {
            self.gpu = gpu
            gpuHistory = Self.appending(MetricSample(value: gpu.utilization), to: gpuHistory)
        }
        if let network = await metrics.network() {
            self.network = network
            networkDownHistory = Self.appending(
                MetricSample(value: network.receivedBytesPerSec), to: networkDownHistory)
            networkUpHistory = Self.appending(
                MetricSample(value: network.sentBytesPerSec), to: networkUpHistory)
        }
        hasLoaded = true
    }

    /// One slow tick: battery + service statuses.
    public func refreshSlowMetrics() async {
        if let battery = await metrics.battery() { self.battery = battery }
        serviceStatuses = await monitor.statuses(for: services)
    }

    /// Card phase: `.loading` before the first batch, then `.content` for a
    /// present value and `.empty` for nil.
    public func cardPhase<T>(_ value: T?) -> DashboardCardPhase {
        if !hasLoaded { return .loading }
        return value == nil ? .empty : .content
    }

    /// Appends a sample to a bounded ring buffer, dropping the oldest samples
    /// past `capacity` (ST-7).
    public static func appending(
        _ sample: MetricSample,
        to history: [MetricSample],
        capacity: Int = DashboardViewModel.historyCapacity
    ) -> [MetricSample] {
        var updated = history
        updated.append(sample)
        if updated.count > capacity {
            updated.removeFirst(updated.count - capacity)
        }
        return updated
    }

    /// The series a chart should render: only the newest `displayWindow`
    /// samples (spec D4). Pure trim — no pre-aggregation, no padding.
    public func displayedSeries(_ history: [MetricSample]) -> [MetricSample] {
        Array(history.suffix(Self.displayWindow))
    }

    /// RAM used percentage for the sparkline history (spec D4). `nil` when the
    /// total is unknown so a zero-size snapshot never yields a divide-by-zero.
    public static func ramUsedPercent(_ ram: RAMSnapshot) -> Double? {
        guard ram.totalBytes > 0 else { return nil }
        return Double(ram.usedBytes) / Double(ram.totalBytes) * 100
    }

    private func runFastLoop() async {
        do {
            for try await _ in AsyncTimerSequence(interval: Self.fastInterval, clock: .continuous) {
                guard !Task.isCancelled else { return }
                await refreshFastMetrics()
            }
        } catch { return }
    }

    private func runSlowLoop() async {
        do {
            for try await _ in AsyncTimerSequence(interval: Self.slowInterval, clock: .continuous) {
                guard !Task.isCancelled else { return }
                await refreshSlowMetrics()
            }
        } catch { return }
    }
}
