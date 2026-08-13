import Foundation

public struct ServiceDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let processName: String
    public let port: Int?

    public init(
        id: String,
        name: String,
        processName: String,
        port: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.processName = processName
        self.port = port
    }
}
