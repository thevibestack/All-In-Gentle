import Foundation

/// A persisted project record that can round-trip through ``ProjectStore``.
///
/// Unlike ``Project``, which represents a single source-provider result,
/// ``StoredProject`` carries the merged sources discovered for a path and a
/// timestamp used to detect stale entries.
public struct StoredProject: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public var sources: [Project.Source]
    public var lastSeen: Date

    public init(
        id: String,
        name: String,
        path: String,
        sources: [Project.Source] = [],
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sources = sources
        self.lastSeen = lastSeen
    }
}
