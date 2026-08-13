import Foundation

public struct TokenUsage: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var project: String
    public var session: String?
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var estimatedCost: Double
    public var timestamp: Date
    public var rawTimeUpdated: Double?

    public init(
        id: String,
        project: String,
        session: String? = nil,
        promptTokens: Int,
        completionTokens: Int,
        estimatedCost: Double,
        timestamp: Date = Date(),
        rawTimeUpdated: Double? = nil
    ) {
        self.id = id
        self.project = project
        self.session = session
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.estimatedCost = estimatedCost
        self.timestamp = timestamp
        self.rawTimeUpdated = rawTimeUpdated
    }
}
