import Foundation

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var role: Role
    public var content: String
    public var timestamp: Date

    public init(
        id: String,
        role: Role,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
}
