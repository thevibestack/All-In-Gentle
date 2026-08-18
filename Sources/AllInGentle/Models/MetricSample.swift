import Foundation

/// A single point of a time-series metric (chart history and ring buffers).
/// Value type, safe to share across concurrency domains (spec ST-9).
public struct MetricSample: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}
