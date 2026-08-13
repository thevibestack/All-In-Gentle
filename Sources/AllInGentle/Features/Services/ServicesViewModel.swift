import Foundation
import Observation

@MainActor
@Observable
public final class ServicesViewModel {
    public private(set) var statuses: [ServiceStatus] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?

    private let monitor: ProcessMonitor
    private let services: [ServiceDescriptor]

    public init(monitor: ProcessMonitor, services: [ServiceDescriptor]) {
        self.monitor = monitor
        self.services = services
    }

    public convenience init() {
        self.init(
            monitor: ProcessMonitor(),
            services: [
                ServiceDescriptor(id: "engram", name: "Engram", processName: "engram", port: 7437),
                ServiceDescriptor(id: "codegraph", name: "CodeGraph", processName: "codegraph"),
                ServiceDescriptor(id: "opencode", name: "OpenCode", processName: "opencode")
            ]
        )
    }

    public func poll() async {
        isLoading = true
        defer { isLoading = false }

        let initial = await monitor.statuses(for: services)
        guard !Task.isCancelled else { return }
        statuses = initial

        do {
            for try await batch in await monitor.updates(for: services) {
                guard !Task.isCancelled else { return }
                statuses = batch
            }
        } catch is CancellationError {
            // Polling stopped because the view disappeared; this is expected.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
