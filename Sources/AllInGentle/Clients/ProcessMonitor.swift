import Foundation

public actor ProcessMonitor {
    private let interval: Duration
    private let runner: any ProcessRunning

    public init(
        interval: Duration = .seconds(5),
        runner: any ProcessRunning = ProcessRunner()
    ) {
        self.interval = interval
        self.runner = runner
    }

    public func updates(for services: [ServiceDescriptor]) -> AsyncThrowingStream<[ServiceStatus], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await _ in AsyncTimerSequence(interval: interval, clock: .continuous) {
                        let statuses = await self.statuses(for: services)
                        continuation.yield(statuses)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func statuses(for services: [ServiceDescriptor]) async -> [ServiceStatus] {
        await withTaskGroup(of: ServiceStatus.self) { group in
            for service in services {
                group.addTask { await self.status(for: service) }
            }
            var results: [ServiceStatus] = []
            for await status in group {
                results.append(status)
            }
            return results
        }
    }

    private func status(for service: ServiceDescriptor) async -> ServiceStatus {
        do {
            let pid = try await pid(for: service.processName)
            let portOpen: Bool
            if let port = service.port {
                portOpen = (try? await portIsListening(port)) ?? false
            } else {
                portOpen = false
            }
            let isRunning = pid != nil || portOpen
            let serviceUptime: TimeInterval?
            if let pid = pid {
                serviceUptime = await elapsedTime(for: pid)
            } else {
                serviceUptime = nil
            }
            return ServiceStatus(
                id: service.id,
                name: service.name,
                isRunning: isRunning,
                pid: pid,
                port: service.port,
                uptime: serviceUptime,
                lastError: nil
            )
        } catch {
            return ServiceStatus(
                id: service.id,
                name: service.name,
                isRunning: false,
                pid: nil,
                port: service.port,
                uptime: nil,
                lastError: error.localizedDescription
            )
        }
    }

    private func pid(for processName: String) async throws -> Int? {
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-eo", "pid,comm"]
        )
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let pidString = String(parts[0])
            let comm = String(parts[1])
            if comm == processName || (comm as NSString).lastPathComponent == processName {
                return Int(pidString)
            }
        }
        return nil
    }

    private func portIsListening(_ port: Int) async throws -> Bool {
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        )
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func elapsedTime(for pid: Int) async -> TimeInterval? {
        do {
            let output = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-p", String(pid), "-o", "etime="]
            )
            return parseElapsedTime(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }

    private func parseElapsedTime(_ value: String) -> TimeInterval? {
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        var remaining = cleaned
        var days: TimeInterval = 0
        if let dashIndex = remaining.firstIndex(of: "-") {
            let dayPart = String(remaining[..<dashIndex])
            days = TimeInterval(dayPart) ?? 0
            remaining = String(remaining[remaining.index(after: dashIndex)...])
        }
        let components = remaining.split(separator: ":").map(String.init)
        let hours = components.count == 3 ? (Double(components[0]) ?? 0) : 0
        let minutesIndex = components.count == 3 ? 1 : 0
        let secondsIndex = components.count == 3 ? 2 : 1
        let minutes = components.count >= minutesIndex + 1 ? (Double(components[minutesIndex]) ?? 0) : 0
        let seconds = components.count >= secondsIndex + 1 ? (Double(components[secondsIndex]) ?? 0) : 0
        return days * 86400 + hours * 3600 + minutes * 60 + seconds
    }
}
