import Foundation

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> String
}

extension ProcessRunning {
    /// Default 30s timeout for call sites that do not pass one.
    public func run(executable: URL, arguments: [String]) async throws -> String {
        try await run(executable: executable, arguments: arguments, timeout: .seconds(30))
    }
}

/// `Process` and `FileHandle` are not `Sendable`; each instance is confined to
/// a single drain/reaper task (or the cancellation handler), so an unchecked
/// box is safe.
private final class SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String],
                    timeout: Duration = .seconds(30)) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Concurrent pipe drains. Each pipe is read synchronously on a
        // background dispatch thread (never the cooperative pool), so a child
        // writing >64KB cannot deadlock the process or the pool. (Async
        // `FileHandle.bytes` iteration was measured to yield 1-byte chunks on
        // this platform — far too slow for large outputs.)
        let stdoutDrain = Task { try await readToEnd(outputPipe.fileHandleForReading) }
        let stderrDrain = Task { try await readToEnd(errorPipe.fileHandleForReading) }
        let processBox = SendableBox(process)

        return try await withTaskCancellationHandler {
            let timedOut = try await awaitExit(processBox, timeout: timeout)

            if timedOut {
                throw AllInGentleError.processTimedOut(
                    "Process \(executable.lastPathComponent) exceeded the \(timeout) timeout"
                )
            }

            // Exit won: pipes reach EOF only after the child closes its write
            // ends, so awaiting both drains after exit is race-free.
            let outputData = (try? await stdoutDrain.value) ?? Data()
            let errorData = (try? await stderrDrain.value) ?? Data()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw AllInGentleError.sourceUnavailable(
                    "Process \(executable.lastPathComponent) exited with \(process.terminationStatus): \(error)"
                )
            }
            return output
        } onCancel: {
            processBox.value.terminate()
        }
    }

    private func readToEnd(_ handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try handle.readToEnd() ?? Data())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func waitForExit(_ process: SendableBox<Process>) async {
        await withCheckedContinuation { continuation in
            process.value.terminationHandler = { _ in
                continuation.resume()
            }
        }
    }

    /// Races child exit against the timeout. Returns `true` when the timeout
    /// wins; `false` when the child exited first. On timeout the child is
    /// terminated inside the group so its exit continuation resolves before
    /// the group scope closes.
    private func awaitExit(_ process: SendableBox<Process>, timeout: Duration) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                await waitForExit(process)
                return false // exited
            }
            group.addTask {
                // ContinuousClock: immune to wall-clock changes.
                try await Task.sleep(for: timeout)
                return true // timed out
            }
            guard let timedOut = try await group.next() else { return false }
            group.cancelAll()
            if timedOut {
                process.value.terminate()
            }
            return timedOut
        }
    }
}

public actor CodeGraphClient {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func projects(at root: String) async throws -> [Project] {
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/find"),
            arguments: [root, "-name", ".codegraph", "-maxdepth", "4", "-type", "d"]
        )
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .compactMap { codegraphPath in
                let parentPath = (codegraphPath as NSString).deletingLastPathComponent
                guard !parentPath.isEmpty else { return nil }
                let name = (parentPath as NSString).lastPathComponent
                return Project(
                    id: codegraphPath,
                    name: name,
                    path: parentPath,
                    source: .codegraph,
                    lastModified: nil
                )
            }
    }
}
