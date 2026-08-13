import Foundation

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public var source: Source
    public var lastModified: Date?

    public init(
        id: String,
        name: String,
        path: String,
        source: Source,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.source = source
        self.lastModified = lastModified
    }

    public enum Source: String, Codable, CaseIterable, Sendable {
        case engram
        case opencode
        case codegraph
        case openspec
    }
}
