import Foundation

public struct SessionSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var project: String
    public var sessionName: String
    public var messageCount: Int
    public var totalTokens: Int
    public var estimatedCost: Double
    public var latestDate: Date

    public init(
        id: String,
        project: String,
        sessionName: String,
        messageCount: Int,
        totalTokens: Int,
        estimatedCost: Double,
        latestDate: Date = Date()
    ) {
        self.id = id
        self.project = project
        self.sessionName = sessionName
        self.messageCount = messageCount
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
        self.latestDate = latestDate
    }
}
