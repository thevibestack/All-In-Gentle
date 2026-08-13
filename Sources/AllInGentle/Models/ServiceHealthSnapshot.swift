import Foundation

/// A lightweight health snapshot for a service or process monitored by the app.
public struct ServiceHealthSnapshot: Codable, Sendable, Equatable {
    public let isRunning: Bool
    public let lastError: String?

    public init(isRunning: Bool, lastError: String? = nil) {
        self.isRunning = isRunning
        self.lastError = lastError
    }
}
