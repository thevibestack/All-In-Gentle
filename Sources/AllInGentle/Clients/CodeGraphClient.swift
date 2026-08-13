import Foundation

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> String
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw AllInGentleError.sourceUnavailable(
                    "Process \(executable.lastPathComponent) exited with \(process.terminationStatus): \(error)"
                )
            }
            return output
        }.value
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
