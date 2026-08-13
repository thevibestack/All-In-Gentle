import Foundation

public struct ServiceStatus: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var isRunning: Bool
    public var pid: Int?
    public var port: Int?
    public var uptime: TimeInterval?
    public var lastError: String?

    public init(
        id: String,
        name: String,
        isRunning: Bool,
        pid: Int? = nil,
        port: Int? = nil,
        uptime: TimeInterval? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isRunning = isRunning
        self.pid = pid
        self.port = port
        self.uptime = uptime
        self.lastError = lastError
    }
}
