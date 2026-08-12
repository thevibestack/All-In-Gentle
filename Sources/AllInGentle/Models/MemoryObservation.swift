import Foundation

public struct MemoryObservation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var project: String?
    public var tags: [String]
    public var createdAt: Date

    public init(
        id: String,
        title: String,
        content: String,
        project: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.project = project
        self.tags = tags
        self.createdAt = createdAt
    }
}
