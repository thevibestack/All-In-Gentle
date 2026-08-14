import Foundation

/// A persisted chat session containing messages and optional project linkage.
///
/// Sessions are stored as JSON in ``Application Support/All-In-Gentle/Sessions``.
/// v1 stores a single provider/model identifier; the actual configuration is
/// resolved from ``PreferencesStore`` when the session is loaded.
public struct ChatSession: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var messages: [ChatMessage]
    public var projectID: String?
    public var modelID: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        messages: [ChatMessage] = [],
        projectID: String? = nil,
        modelID: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.projectID = projectID
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Returns a display title, generating one from the first user message
    /// when no explicit title has been set.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            return ChatSession.generatedTitle(from: firstUserMessage.content)
        }
        return L("chat.session.untitled")
    }

    /// Generates a short title from a user message.
    public static func generatedTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 40
        if trimmed.count <= maxLength { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "…"
    }
}
